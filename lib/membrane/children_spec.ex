defmodule Membrane.ChildrenSpec do
  @moduledoc """
  Structure representing the topology of a pipeline/bin.

  It can be incorporated into a pipeline or a bin by returning
  `t:Membrane.Pipeline.Action.spec_t/0` or `t:Membrane.Bin.Action.spec_t/0`
  action, respectively. This commonly happens within `c:Membrane.Pipeline.handle_init/2`
  and `c:Membrane.Bin.handle_init/2`, but can be done in any other callback also.

  ## Structure
  The most important part of the `Membrane.ChildrenSpec` is the `:structure` field.
  The structure allows specifying the children that need to be spawned in the action, as well as
  links between the children (both the children spawned in that action, and already existing children).

  The children's processes are spawned with the use of `child/3` and `child/4` functions.
  These two functions can be used for spawning nodes of a link in an inline manner:
  ```
  structure = [child(:source, Source) |> child(:filter, %Filter{option: 1}) |> child(:sink, Sink)]
  ```
  or just to spawn children processes, without linking the newly created children:
  ```
  structure = [child(:source, Source),
  child(:filter, Filter),
  child(:sink, Sink)]
  ```

  In case you need to refer to an already existing child (which could be spawned, i.e. in the previous `spec_t` action),
  use `get_child/1` and `get_child/2` functions, as in the example below:
  ```
  structure = [get_child(:already_existing_source) |> child(:this_filter_will_be_spawned, Filter) |> get_child(:already_existing_sink)]
  ```

  The `child/3` and `child/4` functions allow specifying `:get_if_exists` option.
  It might be helpful when you are not certain if the child with given name exists, and, therefore, you are unable to
  choose between `get_child` and `child` functions. After setting the `get_if_exists: true` option in `child/3` and `child/4` functions you can be sure
  that in case a child with a given name already exists, you will simply refer to that child instead of respawning it.
  ```
  structure = [child(:sink, Sink),
  child(:sink, Sink, get_if_exists: true) |> child(:source, Source)]
  ```
  In the example above you can see, that the `:sink` child is created in the first element of the `structure` list.
  In the second element of that list, the `get_if_exists: true` option is used within `child/3`, which will have the same effect as if
  `get_child(:sink)` was used. At the same time, if the `:sink` child wasn't already spawned, it would be created in that link definition.

  ### Links between pads

  `via_in/2` and `via_out/2` functions allow
  specifying pads' names and parameters. If pads are not specified, name `:input`
  is assumed for inputs and `:output` for outputs.

  Sample definition:
  [
  get_child(:source_a)
  |> get_child(:converter)
  |> via_in(:input_a, target_queue_size: 20)
  |> get_child(:mixer),
  get_child(:source_b)
  |> via_out(:custom_output)
  |> via_in(:input_b, options: [mute: true])
  |> get_child(:mixer)
  |> via_in(:input, toilet_capacity: 500)
  |> get_child(:sink)
  ]

  See the docs for `via_in/3` and `via_out/3` for details on pad properties that can be set.
  Links can also contain children's definitions, for example:

  [
  child(:first_element, %Element.With.Options.Struct{option_a: 42})
  |> child(:some_element, Element.Without.Options)
  |> get_child(:element_specified_before)
  ]

  ### Bins

  For bin boundaries, there are special links allowed. The user should define links
  between the bin's input and the first child's input (input-input type) and the last
  child's output and bin output (output-output type). In this case, `bin_input/1`
  and `bin_output/2` should be used.

  Sample definition:

  [
  bin_input() |> get_child(:filter1) |> get_child(:filter2) |> bin_output(:custom_output)
  ]

  ### Dynamic pads

  In most cases, dynamic pads can be linked the same way as static ones, although
  in the following situations, an exact pad reference must be passed instead of a name:

  - When that reference is needed later, for example, to handle a notification related
  to that particular pad instance

  pad = Pad.ref(:output, make_ref())
  [
  get_child(:tee) |> via_out(pad) |> get_child(:sink)
  ]

  - When linking dynamic pads of a bin with its children, for example in
  `c:Membrane.Bin.handle_pad_added/3`

  @impl true
  def handle_pad_added(Pad.ref(:input, _) = pad, _ctx, state) do
  structure = [bin_input(pad) |> get_child(:mixer)]
  {{:ok, spec: %ChildrenSpec{structure: structure}}, state}
  end

  ## Stream sync

  `:stream_sync` field can be used for specifying elements that should start playing
  at the same moment. An example can be audio and video player sinks. This option
  accepts either `:sinks` atom or a list of groups (lists) of elements. Passing `:sinks`
  results in synchronizing all sinks in the pipeline, while passing a list of groups
  of elements synchronizes all elements in each group. It is worth mentioning
  that to keep the stream synchronized all involved elements need to rely on
  the same clock.

  By default, no elements are synchronized.

  Sample definitions:

  ```
  %ChildrenSpec{stream_sync: [[:element1, :element2], [:element3, :element4]]}
  %ChildrenSpec{stream_sync: :sinks}
  ```

  ## Clock provider

  A clock provider is an element that exports a clock that should be used as the pipeline
  clock. The pipeline clock is the default clock used by elements' timers.
  For more information see `Membrane.Element.Base.def_clock/1`.

  ## Crash groups
  A crash group is a logical entity that prevents the whole pipeline from crashing when one of
  its children crash.

  ### Adding children to a crash group

  ```elixir
  structure = [
    child(:some_element_1, %SomeElement{
      # ...
    },
    child(:some_element_2, %SomeElement{
      # ...
    }
  ]

  spec = %ChildrenSpec{structure: children, crash_group: {group_id, :temporary}}
  ```

  The crash group is defined by a two-element tuple, first element is an ID which is of type
  `Membrane.CrashGroup.name_t()`, and the second is a mode. Currently, we support only
  `:temporary` mode which means that Membrane will not make any attempts to restart crashed child.

  In the above snippet, we create new children - `:some_element_1` and `:some_element_2`, we add them
  to the crash group with id `group_id`. Crash of `:some_element_1` or `:some_element_2` propagates
  only to the rest of the members of the crash group and the pipeline stays alive.

  Currently, the crash group covers all children within one or more `ChildrenSpec`s.

  ### Handling crash of a crash group

  When any of the members of the crash group goes down, the callback:
  [`handle_crash_group_down/3`](https://hexdocs.pm/membrane_core/Membrane.Pipeline.html#c:handle_crash_group_down/3)
  is called.

  ```elixir
  @impl true
  def handle_crash_group_down(crash_group_id, ctx, state) do
  # do some stuff in reaction to the crash of the group with id crash_group_id
  end
  ```

  ### Limitations

  At this moment crash groups are only useful for elements with dynamic pads.
  Crash groups work only in pipelines and are not supported in bins.

  ## Log metadata
  `:log_metadata` field can be used to set the `Membrane.Logger` metadata for all children from that
  `Membrane.ChildrenSpec`
  """

  import Membrane.Child, only: [is_child_name?: 1]

  alias Membrane.{Child, Pad}
  alias Membrane.ParentError

  require Membrane.Pad

  defmodule LinkBuilder do
    @moduledoc false

    use Bunch.Access

    defstruct children: [], links: [], status: nil

    @type t :: %__MODULE__{
            children: [Membrane.ChildrenSpec.child_spec_extended_t()],
            links: [map],
            status: status_t
          }

    @type status_t :: :from | :from_pad | :to_pad | :done

    @spec update(t, status_t, Keyword.t()) :: t
    def update(
          %__MODULE__{links: [%{to: to} | _] = links, status: :done} = builder,
          status,
          entries
        ) do
      %__MODULE__{builder | links: [Map.new([from: to] ++ entries) | links], status: status}
    end

    def update(%__MODULE__{links: [link | links]} = builder, status, entries) do
      %__MODULE__{builder | links: [Map.merge(link, Map.new(entries)) | links], status: status}
    end
  end

  @type pad_options_t :: Keyword.t()
  @opaque link_builder_t :: LinkBuilder.t()

  @type child_spec_t :: struct() | module()
  @type child_opts_t :: [get_if_exists: boolean]

  @type child_spec_extension_options_t :: [dont_spawn_if_exists: boolean()]
  @type child_spec_extended_t ::
          {Child.name_t(), child_spec_t(), child_spec_extension_options_t()}

  @type structure_spec_t :: [link_builder_t()]

  @default_child_opts [get_if_exists: false]

  @typedoc """
  Struct used when starting and linking children within a pipeline or a bin.
  """
  @type t :: %__MODULE__{
          structure: structure_spec_t,
          crash_group: Membrane.CrashGroup.t(),
          stream_sync: :sinks | [[Child.name_t()]],
          clock_provider: Child.name_t() | nil,
          node: node() | nil,
          log_metadata: Keyword.t()
        }

  defstruct structure: [],
            crash_group: nil,
            stream_sync: [],
            clock_provider: nil,
            node: nil,
            log_metadata: []

  @doc """
  Used to refer to an existing child at a beggining of a link specification.

  See the _structure_ section of the moduledoc for more information.
  """
  @spec get_child(Child.name_t()) :: link_builder_t()
  def get_child(child_name) do
    %LinkBuilder{links: [%{from: child_name}], status: :from}
  end

  @doc """
  Used to refer to an existing child in a middle of a link specification.

  See the _structure_ section of the moduledoc for more information.
  """
  @spec get_child(link_builder_t(), Child.name_t()) :: link_builder_t()
  def get_child(%LinkBuilder{} = link_builder, child_name) do
    if link_builder.status == :to_pad do
      link_builder
    else
      via_in(link_builder, :input)
    end
    |> LinkBuilder.update(:done, to: child_name)
  end

  @doc """
  Used to spawn an unlinked child or to spawn a child at the beggining of
  a link specification.

  See the _structure_ section of the moduledoc for more information.
  """
  @spec child(
          link_builder_t | Child.name_t(),
          Child.name_t() | child_spec_t(),
          child_spec_t() | child_opts_t()
        ) ::
          link_builder_t()
  def child(child_name, child_spec, opts \\ @default_child_opts)

  def child(%LinkBuilder{} = link_builder, child_name, child_spec) do
    do_child(link_builder, child_name, child_spec, @default_child_opts)
  end

  def child(child_name, child_spec, options) when is_child_name?(child_name) do
    do_child(child_name, child_spec, options)
  end

  def child(_first_arg, _second_arg, _third_arg) do
    raise "Link builder cannot be used as a child name! Perhaps you meant to use get_child/2?"
  end

  defp do_child(child_name, child_spec, opts) do
    child_spec_extended =
      {child_name, child_spec,
       dont_spawn_if_already_exists: Keyword.get(opts, :get_if_exists, false)}

    get_child(child_name) |> Map.update!(:children, &[child_spec_extended | &1])
  end

  @doc """
  Used to spawn a child in the middle of a link specification.

  See the _structure_ section of the moduledoc for more information.
  """
  @spec child(link_builder_t(), Child.name_t(), child_spec_t(), child_opts_t()) ::
          link_builder_t()
  def child(link_builder, child_name, child_spec, opts) do
    do_child(link_builder, child_name, child_spec, opts)
  end

  defp do_child(%LinkBuilder{} = link_builder, child_name, child_spec, opts) do
    child_spec_extended =
      {child_name, child_spec,
       dont_spawn_if_already_exists: Keyword.get(opts, :get_if_exists, false)}

    link_builder
    |> get_child(child_name)
    |> Map.update!(:children, &[child_spec_extended | &1])
  end

  @doc """
  Begins a link with a bin's pad.

  See the _structure_ section of the moduledoc for more information.
  """
  @spec bin_input(Pad.name_t() | Pad.ref_t()) :: link_builder_t() | no_return
  def bin_input(pad \\ :input) do
    :ok = validate_pad_name(pad)

    get_child({Membrane.Bin, :itself})
    |> LinkBuilder.update(:from_pad, from_pad: pad, from_pad_props: %{})
  end

  @doc """
  Specifies output pad name and properties of the preceding child.

  The possible properties are:
  - `options` - If a pad defines options, they can be passed here as a keyword list. Pad options are documented
  in moduledoc of each element. See `Membrane.Element.WithOutputPads.def_output_pad/2` and `Membrane.Bin.def_output_pad/2`
  for information about defining pad options.

  See the _structure_ section of the moduledoc for more information.
  """
  @spec via_out(link_builder_t(), Pad.name_t() | Pad.ref_t(), options: pad_options_t()) ::
          link_builder_t() | no_return
  def via_out(builder, pad, props \\ [])

  def via_out(%LinkBuilder{status: :from_pad}, pad, _props) do
    raise ParentError,
          "Invalid link specification: output #{inspect(pad)} placed after another output or bin's input"
  end

  def via_out(%LinkBuilder{status: :to_pad}, pad, _props) do
    raise ParentError, "Invalid link specification: output #{inspect(pad)} placed after an input"
  end

  def via_out(%LinkBuilder{links: [%{to: {Membrane.Bin, :itself}} | _]}, pad, _props) do
    raise ParentError,
          "Invalid link specification: output #{inspect(pad)} placed after bin's output"
  end

  def via_out(%LinkBuilder{} = builder, pad, props) do
    :ok = validate_pad_name(pad)

    props =
      case Bunch.Config.parse(props, options: [default: []]) do
        {:ok, props} ->
          props

        {:error, reason} ->
          raise ParentError, "Invalid link specification: invalid pad props: #{inspect(reason)}"
      end

    LinkBuilder.update(builder, :from_pad,
      from_pad: pad,
      from_pad_props: props
    )
  end

  @doc """
  Specifies input pad name and properties of the subsequent child.

  The possible properties are:
  - `options` - If a pad defines options, they can be passed here as a keyword list. Pad options are documented
  in moduledoc of each element. See `Membrane.Element.WithInputPads.def_input_pad/2` and `Membrane.Bin.def_input_pad/2`
  for information about defining pad options.

  Additionally, the following properties can be used to adjust the flow control parameters. If set within a bin
  on an input that connects to the bin input, they will be overridden if set when linking to the bin in its parent.

  - `toilet_capacity` - Used when a toilet is created, that is for pull input pads that have push output pads
  linked to them. When a push output produces more buffers than the pull input can consume, the buffers are accumulated
  in a queue called a toilet. If the toilet size grows above its capacity, it overflows by raising an error.
  - `target_queue_size` - The size of the queue of the input pad that Membrane will try to maintain. That allows for fulfilling
  the demands of the element by taking data from the queue while the actual sending of demands is done asynchronously,
  smoothing the processing. Used only for pads working in pull mode with manual demands. See `t:Membrane.Pad.mode_t/0`
  and `t:Membrane.Pad.demand_mode_t/0` for more info.
  - `min_demand_factor` - A factor used to calculate `minimal demand` (`minimal_demand = target_queue_size * min_demand_factor`).
  Membrane won't send smaller demand than `minimal demand`, to reduce demands' overhead. However, the user will always receive
  as many buffers, as demanded, all excess buffers will be queued internally.
  Used only for pads working in pull mode with manual demands. See `t:Membrane.Pad.mode_t/0` and `t:Membrane.Pad.demand_mode_t/0`
  for more info. Defaults to `#{Membrane.Core.Element.InputQueue.default_min_demand_factor()}` (the default may change in the future).
  - `auto_demand_size` - Size of automatically generated demands. Used only for pads working in pull mode with automatic demands.
    See `t:Membrane.Pad.mode_t/0` and `t:Membrane.Pad.demand_mode_t/0` for more info.
  - `throttling_factor` - an integer specifying how frequently should a sender update the number of buffers in the `Toilet`. Defaults to 1,
    meaning, that the sender will update the toilet with each buffer being sent. Setting that factor for elements,
    which are running on the same node, does not have an impact of performance. However, once the sending element and the receiving element are put on different nodes,
    the sender updates the toilet with interprocess messages and setting a bigger `throttling_factor` can reduce the number of messages
    in the system.
    At the same time, setting a greater `throttling_factor` can result in a toilet overflow being detected later.

  See the _structure_ section of the moduledoc for more information.
  """
  @spec via_in(link_builder_t(), Pad.name_t() | Pad.ref_t(),
          options: pad_options_t(),
          toilet_capacity: number | nil,
          target_queue_size: number | nil,
          min_demand_factor: number | nil,
          auto_demand_size: number | nil,
          throttling_factor: number | nil
        ) ::
          link_builder_t() | no_return
  def via_in(builder, pad, props \\ [])

  def via_in(%LinkBuilder{status: :to_pad}, pad, _props) do
    raise ParentError,
          "Invalid link specification: input #{inspect(pad)} placed after another input"
  end

  def via_in(%LinkBuilder{links: [%{to: {Membrane.Bin, :itself}} | _]}, pad, _props) do
    raise ParentError,
          "Invalid link specification: input #{inspect(pad)} placed after bin's output"
  end

  def via_in(%LinkBuilder{} = builder, pad, props) do
    :ok = validate_pad_name(pad)

    props =
      props
      |> Bunch.Config.parse(
        options: [default: []],
        target_queue_size: [default: nil],
        min_demand_factor: [default: nil],
        auto_demand_size: [default: nil],
        toilet_capacity: [default: nil],
        throttling_factor: [default: 1]
      )
      |> case do
        {:ok, props} ->
          props

        {:error, reason} ->
          raise ParentError, "Invalid link specification: invalid pad props: #{inspect(reason)}"
      end

    if builder.status == :from_pad do
      builder
    else
      via_out(builder, :output)
    end
    |> LinkBuilder.update(:to_pad,
      to_pad: pad,
      to_pad_props: props
    )
  end

  @doc """
  Ends a link with a bin's output.

  See the _structure_ section of the moduledoc for more information.
  """
  @spec bin_output(link_builder_t(), Pad.name_t() | Pad.ref_t()) ::
          link_builder_t() | no_return
  def bin_output(builder, pad \\ :output)

  def bin_output(%LinkBuilder{status: :to_pad}, pad) do
    raise ParentError, "Invalid link specification: bin's output #{pad} placed after an input"
  end

  def bin_output(%LinkBuilder{} = builder, pad) do
    :ok = validate_pad_name(pad)

    if builder.status == :from_pad do
      builder
    else
      via_out(builder, :output)
    end
    |> LinkBuilder.update(:to_pad, to_pad: pad, to_pad_props: %{})
    |> get_child({Membrane.Bin, :itself})
  end

  defp validate_pad_name(pad) when Pad.is_pad_name(pad) or Pad.is_pad_ref(pad) do
    :ok
  end

  defp validate_pad_name(pad) do
    raise ParentError, "Invalid link specification: invalid pad name: #{inspect(pad)}"
  end
end
