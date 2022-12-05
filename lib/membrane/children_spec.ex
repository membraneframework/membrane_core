defmodule Membrane.ChildrenSpec do
  @moduledoc """
  A module with functionalities that allow to represent a topology of a pipeline/bin.

  The children specification (commonly referred to as a "children_spec") is represented by the following type:
  `t:t/0`. It consists of two parts - a children's specification and the children's specification options.

  The children's specification describes the desired topology and can be incorporated into a pipeline or a bin by returning
  `t:Membrane.Pipeline.Action.spec_t/0` or `t:Membrane.Bin.Action.spec_t/0`
  action, respectively. This commonly happens within `c:Membrane.Pipeline.handle_init/2`
  and `c:Membrane.Bin.handle_init/2`, but can be done in any other callback also.

  ## Children's specification
  The children's specification allows specifying the children that need to be spawned in the action, as well as
  links between the children (both the children spawned in that action, and already existing children).

  The children's processes are spawned with the use of `child/1`, `child/2`, `child/3` and `child/4` functions.
  These functions can be used for spawning nodes of a link in an inline manner:
  ```
    spec = [child(:source, Source) |> child(:filter, %Filter{option: 1}) |> child(:sink, Sink)]
  ```
  or just to spawn children processes, without linking the newly created children:
  ```
    spec = [child(:source, Source),
      child(:filter, Filter),
      child(:sink, Sink)
    ]
  ```

  Providing a child name is not necessary - you can spawn an anonymous child if you do not
  need to refer to that child later on:
  ```
    spec = child(Source) |> child(Filter)
  ```
  Children created that way will have their automatically generated identifier consisting of a module
  name and a random unique reference number, so that you will be able to distinguish between anonymous
  children i.e. in log prints.

  In case you need to refer to an already existing child (which could be spawned, i.e. in the previous `spec_t` action),
  use `get_child/1` and `get_child/2` functions, as in the example below:
  ```
    spec = [get_child(:already_existing_source) |> child(:this_filter_will_be_spawned, Filter) |> get_child(:already_existing_sink)]
  ```

  The `child` functions allow specifying `:get_if_exists` option.
  It might be helpful when you are not certain if the child with the given name exists, and, therefore, you are unable to
  choose between `get_child` and `child` functions. After setting the `get_if_exists: true` option in `child/3` and `child/4` functions you can be sure
  that in case a child with a given name already exists, you will simply refer to that child instead of respawning it.
  ```
    spec = [child(:sink, Sink),
      child(:sink, Sink, get_if_exists: true) |> child(:source, Source)]
  ```
  In the example above you can see, that the `:sink` child is created in the first element of the `spec` list.
  In the second element of that list, the `get_if_exists: true` option is used within `child/3`, which will have the same effect as if
  `get_child(:sink)` was used. At the same time, if the `:sink` child wasn't already spawned, it would be created in that link definition.
  Please note that it makes sense to use `:get_if_exists` option only with named children.

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
    spec = [bin_input(pad) |> get_child(:mixer)]
    {{:ok, spec: spec}, state}
  end

  ## Children's specification options
  ### Stream sync

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
  children = ...
    {children, stream_sync: [[:element1, :element2], [:element3, :element4]]}
    {children, stream_sync: :sinks}
  ```

  ### Clock provider

  A clock provider is an element that exports a clock that should be used as the pipeline
  clock. The pipeline clock is the default clock used by elements' timers.
  For more information see `Membrane.Element.Base.def_clock/1`.

  ### Children groups
  Children groups allow aggregating the spawned children into easily identifiable groups.
  With the use of them, it is possible to refer to all the children of the group with a single identifier.
  Example:
  ```
    spec1 = {links1, group: :first_children_group}
    spec2 = {links2, group: :second_children_group}
  ```
  The children spawned within `links1` specification will be put inside `:first_children_group`, whereas the
  children spawned within `links2` specification will be put inside `second_children_group`.

  In order to refer to a child which resides inside the children group, you need to use the `Membrane.Child.ref/2` function,
  as in the example below:
   ```
    spec1 = {child(:source, Source), group: :first_group)
    spec2 = get_child(Membrane.Child.ref(:source, group: :first_group)) |> child(:sink, Sink)
   ```

  Later on, the children from a given group can be referred with their `group`, as in the example below:
  ```
    actions = [remove_children: :first_children_group]
  ```
  With the action defined above, all the children from the `:first_children_group` can be removed at once.

  ### Crash groups
  A crash group is a logical entity that prevents the whole pipeline from crashing when one of
  its children crashes. A crash group is defined with the use of two children specification options:
  * `group` - which acts as a crash group identifier
  * `crash_group_mode` - its value specifies the behavior of children in the crash group. Currently, we support only
  `:temporary` mode which means that Membrane will not make any attempts to restart crashed child.

  #### Adding children to a crash group

  ```
  spec = [
    child(:some_element_1, %SomeElement{
      # ...
    },
    child(:some_element_2, %SomeElement{
      # ...
    }
  ]

  spec = {spec, group: group_id, crash_group_mode: :temporary}
  ```

  In the above snippet, we create new children - `:some_element_1` and `:some_element_2`, we add them
  to the crash group with id `group_id`. Crash of `:some_element_1` or `:some_element_2` propagates
  only to the rest of the members of the crash group and the pipeline stays alive.

  #### Handling crash of a crash group

  When any of the members of the crash group goes down, the callback:
  [`handle_crash_group_down/3`](https://hexdocs.pm/membrane_core/Membrane.Pipeline.html#c:handle_crash_group_down/3)
  is called.

  ```
  @impl true
  def handle_crash_group_down(crash_group_id, ctx, state) do
    # do some stuff in reaction to the crash of the group with id crash_group_id
  end
  ```

  #### Limitations

  At this moment crash groups are only useful for elements with dynamic pads.
  Crash groups work only in pipelines and are not supported in bins.

  ### Log metadata
  `:log_metadata` field can be used to set the `Membrane.Logger` metadata for all children in the given children specification.

  ## Nesting children's specifications
  The children's specifications can be nested within themselves.

  Consider the following children's specifications:
  ```
  {[
    child(:a, A) |> child(:b, B),
    {child(:c, C), crash_group:
    {:second, :temporary}}
  ], crash_group_mode: :temporary, group: :first, node: some_node}
  ```

  Child `:c` will be spawned in the `:second` crash group, while children `:a` and `:b` will be spawned in the `:first` crash group.
  Furthermore, since the inner children specification does not define the `:node` option, it will be inherited from the outer children specification.
  That means that child `:c` will be spawned on the `some_node` node, along with children `:a` and `:b`.

  """

  import Membrane.Child, only: [is_child_name?: 1]

  alias Membrane.{Child, Pad}
  alias Membrane.ParentError

  require Membrane.Pad

  defmodule Builder do
    @moduledoc false

    use Bunch.Access

    @typep child_options_map_t :: %{get_if_exists: boolean}

    @type child_spec_t ::
            {{:child_name, Child.name_t()} | {:child_ref, Child.name_t()},
             Membrane.ChildrenSpec.child_definition_t(), child_options_map_t()}

    @type status_t :: :from_pad | :to_pad | :done

    @type t :: %__MODULE__{
            children: [child_spec_t()],
            links: [map],
            status: status_t,
            from_pad: Membrane.Pad.name_t() | Membrane.Pad.ref_t() | nil,
            from_pad_props: %{} | nil,
            to_pad: Membrane.Pad.name_t() | Membrane.Pad.ref_t() | nil,
            to_pad_props: %{} | nil,
            link_starting_child: Child.name_t()
          }

    defstruct children: [],
              links: [],
              status: :done,
              from_pad: nil,
              from_pad_props: nil,
              to_pad: nil,
              to_pad_props: nil,
              link_starting_child: nil

    @spec finish_link(t(), Child.name_t()) :: t()
    def finish_link(%__MODULE__{status: :to_pad} = builder, child_name) do
      new_link = %{
        from: builder.link_starting_child,
        from_pad: builder.from_pad,
        from_pad_props: builder.from_pad_props,
        to: child_name,
        to_pad: builder.to_pad,
        to_pad_props: builder.to_pad_props
      }

      %Builder{
        builder
        | status: :done,
          link_starting_child: child_name,
          links: [new_link | builder.links]
      }
    end
  end

  @opaque builder_t :: Builder.t()

  @type pad_options_t :: Keyword.t()

  @type child_definition_t :: struct() | module()

  @type child_options_t :: [get_if_exists: boolean]
  @default_child_options [get_if_exists: [default: false]]

  @type children_spec_options_t :: [
          group: Child.group_t(),
          crash_group_mode: Membrane.CrashGroup.mode_t() | nil,
          stream_sync: :sinks | [[Child.name_t()]],
          clock_provider: Child.name_t() | nil,
          node: node() | nil,
          log_metadata: Keyword.t()
        ]

  @typedoc """
  Used to describe the inner topology of the pipeline/bin.
  """
  @type t :: builder_t() | [t()] | {t(), children_spec_options_t()}

  @doc """
  Used to refer to an existing child at a beginning of a link specification.

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec get_child(Child.name_t()) :: builder_t()
  def get_child(child_name) do
    do_get_child(child_name)
  end

  @doc """
  Used to refer to an existing child in a middle of a link specification.

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec get_child(builder_t(), Child.name_t()) :: builder_t()
  def get_child(%Builder{} = builder, child_ref) do
    do_get_child(builder, child_ref)
  end

  defp do_get_child(child_ref) do
    %Builder{link_starting_child: {:child_ref, child_ref}}
  end

  defp do_get_child(builder, child_ref) do
    if builder.status == :to_pad do
      builder
    else
      via_in(builder, :input)
    end
    |> Builder.finish_link({:child_ref, child_ref})
  end

  @doc """
  Used to spawn an anonymous child at the beggining of the link specification.

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec child(child_definition_t()) :: builder_t()
  def child(child_definition) do
    child_module = get_module(child_definition)
    child_name = {child_module, make_ref()}
    do_child(child_name, child_definition, [])
  end

  @doc """
  Used to spawn a named child at the beggining of the link
  specification or to spawn an anynomous child.

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec child(Child.name_t(), child_definition_t()) :: builder_t()
  @spec child(builder_t(), child_definition_t()) :: builder_t()
  @spec child(child_definition_t(), child_options_t()) :: builder_t()
  def child(child_name, child_definition) when is_child_name?(child_name) do
    do_child(child_name, child_definition, [])
  end

  def child(%Builder{} = builder, child_definition) do
    child_module = get_module(child_definition)
    child_name = {child_module, make_ref()}
    do_child(builder, child_name, child_definition, [])
  end

  def child(child_definition, opts) do
    child_module = get_module(child_definition)
    child_name = {child_module, make_ref()}
    do_child(child_name, child_definition, opts)
  end

  @doc """
  Used to spawn a named child or an anonymous child in the middle
  of the link specification.

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec child(builder_t(), Child.name_t(), child_definition_t()) :: builder_t()
  @spec child(builder_t(), child_definition_t(), child_options_t()) :: builder_t()
  @spec child(Child.name_t(), child_definition_t(), child_options_t()) :: builder_t()
  def child(first_arg, second_arg, third_arg)

  def child(%Builder{} = builder, child_name, child_definition)
      when is_child_name?(child_name) do
    do_child(builder, child_name, child_definition, [])
  end

  def child(%Builder{} = builder, child_definition, options) do
    child_module = get_module(child_definition)
    child_name = {child_module, make_ref()}
    do_child(builder, child_name, child_definition, options)
  end

  def child(child_name, child_definition, options) when is_child_name?(child_name) do
    do_child(child_name, child_definition, options)
  end

  def child(_first_arg, _second_arg, _third_arg) do
    raise "Improper child name! Perhaps you meant to use get_child/2 while building your link?"
  end

  @doc """
  Used to spawn a named child in the middle of a link specification.

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec child(builder_t(), Child.name_t(), child_definition_t(), child_options_t()) :: builder_t()
  def child(builder, child_name, child_definition, opts) do
    do_child(builder, child_name, child_definition, opts)
  end

  defp do_child(child_name, child_definition, opts) do
    ensure_is_child_definition!(child_definition)
    {:ok, opts} = Bunch.Config.parse(opts, @default_child_options)
    child_name = {:child_name, child_name}
    child_spec = {child_name, child_definition, opts}
    %Builder{children: [child_spec], link_starting_child: child_name}
  end

  defp do_child(%Builder{} = builder, child_name, child_definition, opts) do
    ensure_is_child_definition!(child_definition)
    {:ok, opts} = Bunch.Config.parse(opts, @default_child_options)
    child_name = {:child_name, child_name}
    child_spec = {child_name, child_definition, opts}

    if builder.status == :to_pad do
      builder
    else
      via_in(builder, :input)
    end
    |> Builder.finish_link(child_name)
    |> then(&%Builder{&1 | children: [child_spec | &1.children]})
  end

  @doc """
  Begins a link with a bin's pad.

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec bin_input(Pad.name_t() | Pad.ref_t()) :: builder_t() | no_return
  def bin_input(pad \\ :input) do
    :ok = validate_pad_name(pad)

    get_child({Membrane.Bin, :itself})
    |> then(&%Builder{&1 | status: :from_pad, from_pad: pad, from_pad_props: %{}})
  end

  @doc """
  Ends a link with a bin's output.

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec bin_output(builder_t(), Pad.name_t() | Pad.ref_t()) :: builder_t() | no_return
  def bin_output(builder, pad \\ :output)

  def bin_output(%Builder{status: :to_pad}, pad) do
    raise ParentError, "Invalid link specification: bin's output #{pad} placed after an input"
  end

  def bin_output(%Builder{} = builder, pad) do
    :ok = validate_pad_name(pad)

    if builder.status == :from_pad do
      builder
    else
      via_out(builder, :output)
    end
    |> then(&%Builder{&1 | status: :to_pad, to_pad: pad, to_pad_props: %{}})
    |> get_child({Membrane.Bin, :itself})
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

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec via_in(builder_t(), Pad.name_t() | Pad.ref_t(),
          options: pad_options_t(),
          toilet_capacity: number | nil,
          target_queue_size: number | nil,
          min_demand_factor: number | nil,
          auto_demand_size: number | nil,
          throttling_factor: number | nil
        ) :: builder_t() | no_return
  def via_in(builder, pad, props \\ [])

  def via_in(%Builder{status: :to_pad}, pad, _props) do
    raise ParentError,
          "Invalid link specification: input #{inspect(pad)} placed after another input"
  end

  def via_in(%Builder{links: [%{to: {Membrane.Bin, :itself}} | _]}, pad, _props) do
    raise ParentError,
          "Invalid link specification: input #{inspect(pad)} placed after bin's output"
  end

  def via_in(%Builder{} = builder, pad, props) do
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
    |> then(&%Builder{&1 | status: :to_pad, to_pad: pad, to_pad_props: Enum.into(props, %{})})
  end

  @doc """
  Specifies output pad name and properties of the preceding child.

  The possible properties are:
  - `options` - If a pad defines options, they can be passed here as a keyword list. Pad options are documented
  in moduledoc of each element. See `Membrane.Element.WithOutputPads.def_output_pad/2` and `Membrane.Bin.def_output_pad/2`
  for information about defining pad options.

  See the _Children's specification_ section of the moduledoc for more information.
  """
  @spec via_out(builder_t(), Pad.name_t() | Pad.ref_t(), options: pad_options_t()) ::
          builder_t() | no_return
  def via_out(builder, pad, props \\ [])

  def via_out(%Builder{status: :from_pad}, pad, _props) do
    raise ParentError,
          "Invalid link specification: output #{inspect(pad)} placed after another output or bin's input"
  end

  def via_out(%Builder{status: :to_pad}, pad, _props) do
    raise ParentError, "Invalid link specification: output #{inspect(pad)} placed after an input"
  end

  def via_out(%Builder{links: [%{to: {Membrane.Bin, :itself}} | _]}, pad, _props) do
    raise ParentError,
          "Invalid link specification: output #{inspect(pad)} placed after bin's output"
  end

  def via_out(%Builder{status: :done} = builder, pad, props) do
    :ok = validate_pad_name(pad)

    props =
      case Bunch.Config.parse(props, options: [default: []]) do
        {:ok, props} ->
          props

        {:error, reason} ->
          raise ParentError, "Invalid link specification: invalid pad props: #{inspect(reason)}"
      end

    %Builder{
      builder
      | status: :from_pad,
        from_pad: pad,
        from_pad_props: Enum.into(props, %{})
    }
  end

  defp validate_pad_name(pad) when Pad.is_pad_name(pad) or Pad.is_pad_ref(pad) do
    :ok
  end

  defp validate_pad_name(pad) do
    raise ParentError, "Invalid link specification: invalid pad name: #{inspect(pad)}"
  end

  defp get_module(%module{}), do: module
  defp get_module(module), do: module

  defp ensure_is_child_definition!(child_definition) do
    module = get_module(child_definition)

    unless is_atom(module) and
             (Membrane.Element.element?(module) or Membrane.Bin.bin?(module)) do
      raise ParentError, not_child: child_definition
    end
  end
end
