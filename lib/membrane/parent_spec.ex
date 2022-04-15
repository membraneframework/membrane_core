defmodule Membrane.ParentSpec do
  @moduledoc """
  Structure representing the topology of a pipeline/bin.

  It can be incorporated into a pipeline or a bin by returning
  `t:Membrane.Pipeline.Action.spec_t/0` or `t:Membrane.Bin.Action.spec_t/0`
  action, respectively. This commonly happens within `c:Membrane.Pipeline.handle_init/1`
  and `c:Membrane.Bin.handle_init/1`, but can be done in any other callback also.

  ## Children

  Children that should be spawned when the pipeline/bin starts can be defined
  with the `:children` field.
  You have to set it to a map, where keys are valid children names (`t:Membrane.Child.name_t/0`)
  that are unique within this pipeline/bin and values are either child's module or
  struct of that module.

  Sample definitions:

      %{
        first_element: %Element.With.Options.Struct{option_a: 42},
        some_element: Element.Without.Options,
        some_bin: Bin.Using.Default.Options
      }

  ## Links

  Links that should be made when the children are spawned can be defined with the
  `:links` field. Links can be defined with the use of `link/1` and `to/2` functions
  that allow specifying elements linked, and `via_in/2` and `via_out/2` that allow
  specifying pads' names and parameters. If pads are not specified, name `:input`
  is assumed for inputs and `:output` for outputs.

  Sample definition:

      [
        link(:source_a)
        |> to(:converter)
        |> via_in(:input_a, target_queue_size: 20)
        |> to(:mixer),
        link(:source_b)
        |> via_out(:custom_output)
        |> via_in(:input_b, options: [mute: true])
        |> to(:mixer)
        |> via_in(:input, toilet_capacity: 500)
        |> to(:sink)
      ]

  See the docs for `via_in/3` and `via_out/3` for details on pad properties that can be set.
  Links can also contain children definitions, for example:

      [
        link(:first_element, %Element.With.Options.Struct{option_a: 42})
        |> to(:some_element, Element.Without.Options)
        |> to(:element_specified_in_children)
      ]

  Which is particularly convenient for creating links conditionally:

      maybe_link = &to(&1, :some_element, Some.Element)
      [
        link(:first_element)
        |> then(if condition?, do: maybe_link, else: & &1)
        |> to(:another_element)
      ]

   You can also use `link_linear/1` in order to link subsequent children using default pads
   (linking `:input` to `:output` of previous element). That might be especially helpful when creating
   testing pipelines.

      children = [source: Some.Source, filter: Some.Filter, sink: Some.Sink]
      links = link_linear(children)

  ### Bins

  For bins boundaries, there are special links allowed. The user should define links
  between the bin's input and the first child's input (input-input type) and last
  child's output and bin output (output-output type). In this case, `link_bin_input/1`
  and `to_bin_output/2` should be used.

  Sample definition:

      [
        link_bin_input() |> to(:filter1) |> to(:filter2) |> to_bin_output(:custom_output)
      ]

  ### Dynamic pads

  In most cases, dynamic pads can be linked the same way as static ones, although
  in the following situations, exact pad reference must be passed instead of a name:

  - When that reference is needed later, for example, to handle a notification related
  to that particular pad instance

        pad = Pad.ref(:output, make_ref())
        [
          link(:tee) |> via_out(pad) |> to(:sink)
        ]

  - When linking dynamic pads of a bin with its children, for example in
  `c:Membrane.Bin.handle_pad_added/3`

        @impl true
        def handle_pad_added(Pad.ref(:input, _) = pad, _ctx, state) do
          links = [link_bin_input(pad) |> to(:mixer)]
          {{:ok, spec: %ParentSpec{links: links}}, state}
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
    %ParentSpec{stream_sync: [[:element1, :element2], [:element3, :element4]]}
    %ParentSpec{stream_sync: :sinks}
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
  children = %{
    :some_element_1 => %SomeElement{
      # ...
    },
    :some_element_2 => %SomeElement{
      # ...
    }
  }

  spec = %ParentSpec{children: children, crash_group: {group_id, :temporary}}
  ```

  The crash group is defined by a two-element tuple, first element is an ID which is of type
  `Membrane.CrashGroup.name_t()`, and the second is a mode. Currently, we support only
  `:temporary` mode which means that Membrane will not make any attempts to restart crashed child.

  In the above snippet, we create new children - `:some_element_1` and `:some_element_2`, we add it
  to the crash group with id `group_id`. Crash of `:some_element_1` or `:some_element_2` propagates
  only to the rest of the members of the crash group and the pipeline stays alive.

  Currently, crash group covers all children within one or more `ParentSpec`s.

  ### Handling crash of a crash group

  When any of the members of the crash group goes down, the callback:
  [`handle_crash_group_down/3`](https://hexdocs.pm/membrane_core/Membrane.Pipeline.html#c:handle_crash_group_down/3)
  is called.

  ```elixir
  @impl true
  def handle_crash_group_down(crash_group_id, ctx, state) do
    # do some stuff in reaction to crash of group with id crash_group_id
  end
  ```

  ### Limitations

  At this moment crash groups are only useful for elements with dynamic pads.
  Crash groups work only in pipelines and are not supported in bins.

  ## Log metadata
  `:log_metadata` field can be used to set the `Membrane.Logger` metadata for all children from that
  `Membrane.ParentSpec`
  """

  alias Membrane.{Child, Pad}
  alias Membrane.ParentError

  require Membrane.Pad

  defmodule LinkBuilder do
    @moduledoc false

    use Bunch.Access

    defstruct children: [], links: [], status: nil

    @type t :: %__MODULE__{
            children: [{Child.name_t(), module | struct}],
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

  @opaque link_builder_t :: LinkBuilder.t()

  @type child_spec_t :: module | struct

  @type children_spec_t ::
          [{Child.name_t(), child_spec_t}]
          | %{Child.name_t() => child_spec_t}

  @type pad_options_t :: Keyword.t()

  @type links_spec_t :: [link_builder_t() | links_spec_t]

  @type crash_group_spec_t :: {any(), :temporary} | nil
  @typedoc """
  Struct used when starting and linking children within a pipeline or a bin.
  """
  @type t :: %__MODULE__{
          children: children_spec_t,
          links: links_spec_t,
          crash_group: crash_group_spec_t() | nil,
          stream_sync: :sinks | [[Child.name_t()]],
          clock_provider: Child.name_t() | nil,
          node: node() | nil,
          log_metadata: Keyword.t()
        }

  defstruct children: %{},
            links: [],
            crash_group: nil,
            stream_sync: [],
            clock_provider: nil,
            node: nil,
            log_metadata: []

  @doc """
  Begins a link.

  See the _links_ section of the moduledoc for more information.
  """
  @spec link(Child.name_t()) :: link_builder_t()
  def link(child_name) do
    %LinkBuilder{links: [%{from: child_name}], status: :from}
  end

  @doc """
  Defines a child and begins a link with it.

  See the _links_ section of the moduledoc for more information.
  """
  @spec link(Child.name_t(), child_spec_t()) :: link_builder_t()
  def link(child_name, child_spec) do
    link(child_name) |> Map.update!(:children, &[{child_name, child_spec} | &1])
  end

  @doc """
  Begins a link with a bin's pad.

  See the _links_ section of the moduledoc for more information.
  """
  @spec link_bin_input(Pad.name_t() | Pad.ref_t()) :: link_builder_t() | no_return
  def link_bin_input(pad \\ :input) do
    :ok = validate_pad_name(pad)

    link({Membrane.Bin, :itself})
    |> LinkBuilder.update(:from_pad, from_pad: pad, from_pad_props: %{})
  end

  @doc """
  Specifies output pad name and properties of the preceding child.

  The possible properties are:
  - `options` - If a pad defines options, they can be passed here as a keyword list. Pad options are documented
    in moduledoc of each element. See `Membrane.Element.WithOutputPads.def_output_pad/2` and `Membrane.Bin.def_output_pad/2`
    for information about defining pad options.

  See the _links_ section of the moduledoc for more information.
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
    in a queue called toilet. If the toilet size grows above its capacity, it overflows by raising an error.
  - `target_queue_size` - The size of the queue of the input pad that Membrane will try to maintain. That allows for fulfilling
    the demands of the element by taking data from the queue while the actual sending of demands is done asynchronously,
    smoothing the processing. Used only for pads working in pull mode with manual demands. See `t:Membrane.Pad.mode_t/0`
    and `t:Membrane.Pad.demand_mode_t/0` for more info.
  - `min_demand_factor` - A factor used to calculate `minimal demand` (`minimal_demand = target_queue_size * min_demand_factor`).
    Membrane won't send smaller demand that `minimal demand`, to reduce demands' overhead. However, user will always receive
    as many buffers as they actually demanded, all excess buffers will be queued internally.
    Used only for pads working in pull mode with manual demands. See `t:Membrane.Pad.mode_t/0` and `t:Membrane.Pad.demand_mode_t/0`
    for more info. Defaults to `#{Membrane.Core.Element.InputQueue.default_min_demand_factor()}` (the default may change in the future).
  - `auto_demand_size` - Size of automatically generated demands. Used only for pads working in pull mode with automatic demands.
    See `t:Membrane.Pad.mode_t/0` and `t:Membrane.Pad.demand_mode_t/0` for more info.

  See the _links_ section of the moduledoc for more information.
  """
  @spec via_in(link_builder_t(), Pad.name_t() | Pad.ref_t(),
          options: pad_options_t(),
          toilet_capacity: number | nil,
          target_queue_size: number | nil,
          min_demand_factor: number | nil,
          auto_demand_size: number | nil
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
        toilet_capacity: [default: nil]
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
  Continues or ends a link.

  See the _links_ section of the moduledoc for more information.
  """
  @spec to(link_builder_t(), Child.name_t()) :: link_builder_t() | no_return
  def to(%LinkBuilder{links: [%{to: {Membrane.Bin, :itself}} | _]}, child_name) do
    raise ParentError,
          "Invalid link specification: child #{inspect(child_name)} placed after bin's output"
  end

  def to(%LinkBuilder{} = builder, child_name) do
    if builder.status == :to_pad do
      builder
    else
      via_in(builder, :input)
    end
    |> LinkBuilder.update(:done, to: child_name)
  end

  @doc """
  Defines a child and continues or ends a link with it.

  See the _links_ section of the moduledoc for more information.
  """
  @spec to(link_builder_t(), Child.name_t(), child_spec_t()) :: link_builder_t() | no_return
  def to(%LinkBuilder{} = builder, child_name, child_spec) do
    builder |> to(child_name) |> Map.update!(:children, &[{child_name, child_spec} | &1])
  end

  @doc """
  Ends a link with a bin's output.

  See the _links_ section of the moduledoc for more information.
  """
  @spec to_bin_output(link_builder_t(), Pad.name_t() | Pad.ref_t()) ::
          link_builder_t() | no_return
  def to_bin_output(builder, pad \\ :output)

  def to_bin_output(%LinkBuilder{status: :to_pad}, pad) do
    raise ParentError, "Invalid link specification: bin's output #{pad} placed after an input"
  end

  def to_bin_output(builder, pad) do
    :ok = validate_pad_name(pad)

    if builder.status == :from_pad do
      builder
    else
      via_out(builder, :output)
    end
    |> LinkBuilder.update(:to_pad, to_pad: pad, to_pad_props: %{})
    |> to({Membrane.Bin, :itself})
  end

  @doc """
  Links subsequent children using default pads (linking `:input` to `:output` of
  previous element).

  ## Example

      Membrane.ParentSpec.link_linear([el1: MembraneElement1, el2: MembraneElement2])
  """
  @spec link_linear(children :: [child_spec_t()]) :: links_spec_t()
  def link_linear([]) do
    []
  end

  def link_linear(children) when is_list(children) do
    [{first_child_name, first_child_spec} | other_children] = children

    links =
      other_children
      |> Enum.reduce(link(first_child_name, first_child_spec), fn {child_name, child_spec},
                                                                  builder ->
        to(builder, child_name, child_spec)
      end)

    [links]
  end

  defp validate_pad_name(pad) when Pad.is_pad_name(pad) or Pad.is_pad_ref(pad) do
    :ok
  end

  defp validate_pad_name(pad) do
    raise ParentError, "Invalid link specification: invalid pad name: #{inspect(pad)}"
  end
end
