defmodule Membrane.ParentSpec do
  @moduledoc """
  Structure representing topology of a pipeline/bin.

  It can be incorporated into a pipeline or a bin by returning
  `t:Membrane.Parent.Action.spec_action_t/0` action. This commonly happens within
  `c:Membrane.Pipeline.handle_init/1` and `c:Membrane.Bin.handle_init/1`, but can
  be done in any other callback also.

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
  `:links` field. Links can be defined with use of `link/1` and `to/2` functions
  that allow to specify elements linked, and `via_in/2` and `via_out/2` that allow
  to specify pads' names and parameters. If pads are not specified, name `:input`
  is assumed for inputs and `:output` for outputs.

  Sample definition:

      [
        link(:source_a)
        |> to(:converter)
        |> via_in(:input_a, buffer: [preferred_size: 20_000])
        |> to(:mixer),
        link(:source_b)
        |> via_out(:custom_output)
        |> via_in(:input_b, pad: [mute: true])
        |> to(:mixer)
        |> via_in(:input, [warn_size: 264_000, fail_size: 300_000])
        |> to(:sink)
      ]

  ### Bins

  For bins boundaries there are special links allowed. User should define links
  between bin's input and first child's input (input-input type) and last
  child's output and bin output (output-output type). In this case, `link_bin_input/2`
  and `to_bin_output/3` should be used.

  Sample definition:

      [
        link_bin_input() |> to(:filter1) |> to(:filter2) |> to_bin_output(:custom_output)
      ]

  ### Dynamic pads

  In most cases dynamic pads can be linked the same way as static ones, although
  in the following situations exact pad reference must be passed instead of a name:

  - When that reference is needed later, for example to handle a notification related
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
  accepts either `:sinks` atom or list of groups (lists) of elements. Passing `:sinks`
  results in synchronizing all sinks in the pipeline, while passing list of groups
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

  Clock provider is an element that exports clock that should be used as the pipeline
  clock. The pipeline clock is the default clock used by elements' timers.
  For more information see `Membrane.Element.Base.def_clock/1`.

  """

  alias Membrane.{Child, Pad}
  alias Membrane.Core.InputBuffer
  alias Membrane.ParentError

  require Membrane.Pad

  defmodule LinkBuilder do
    @moduledoc false
    defstruct links: [], status: nil

    @type t :: %__MODULE__{
            links: [map],
            status: status_t
          }

    @type status_t :: :from | :output | :input | :done

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

  @type child_spec_t :: module | struct

  @type children_spec_t ::
          [{Child.name_t(), child_spec_t}]
          | %{Child.name_t() => child_spec_t}

  @typedoc """
  Options passed to the child when linking its pad with a different one.

  The allowed options are:
  * `:buffer` - keyword allowing to configure `Membrane.Core.InputBuffer` between elements. Valid only for input pads.
    See `t:Membrane.Core.InputBuffer.props_t/0` for configurable properties.
  * `:options` - any child-specific options that will be available in `Membrane.Pad.Data` struct.
  """
  @type pad_props_t :: [
          {:buffer, InputBuffer.props_t()}
          | {:options, Keyword.t()}
        ]

  @type links_spec_t :: [LinkBuilder.t() | links_spec_t]

  @typedoc """
  Struct used when starting and linking children within a pipeline or a bin.
  """
  @type t :: %__MODULE__{
          children: children_spec_t,
          links: links_spec_t,
          stream_sync: :sinks | [[Child.name_t()]],
          clock_provider: Child.name_t()
        }

  @valid_pad_prop_keys [:options, :buffer]

  defstruct children: %{},
            links: [],
            stream_sync: [],
            clock_provider: nil

  @doc """
  Begins a link.

  See the _links_ section of the moduledoc for more information.
  """
  @spec link(Child.name_t()) :: LinkBuilder.t()
  def link(child_name) do
    %LinkBuilder{links: [%{from: child_name}], status: :from}
  end

  @doc """
  Begins a link with a bin's pad.

  See the _links_ section of the moduledoc for more information.
  """
  @spec link_bin_input(Pad.name_t() | Pad.ref_t(), pad_props_t) :: LinkBuilder.t() | no_return
  def link_bin_input(pad \\ :input, props \\ []) do
    link({Membrane.Bin, :itself}) |> via_out(pad, props)
  end

  @doc """
  Specifies output pad name and properties of the preceding child.

  See the _links_ section of the moduledoc for more information.
  """
  @spec via_out(LinkBuilder.t(), Pad.name_t() | Pad.ref_t(), pad_props_t) ::
          LinkBuilder.t() | no_return
  def via_out(builder, pad, props \\ [])

  def via_out(%LinkBuilder{status: :output}, pad, _props) do
    raise ParentError,
          "Invalid link specification: output #{inspect(pad)} placed after another output or bin's input"
  end

  def via_out(%LinkBuilder{status: :input}, pad, _props) do
    raise ParentError, "Invalid link specification: output #{inspect(pad)} placed after an input"
  end

  def via_out(%LinkBuilder{} = builder, pad, props) do
    :ok = validate_pad_name(pad)
    :ok = validate_pad_props(props)

    LinkBuilder.update(builder, :output,
      output: pad,
      output_props: props
    )
  end

  @doc """
  Specifies input pad name and properties of the subsequent child.

  See the _links_ section of the moduledoc for more information.
  """
  @spec via_in(LinkBuilder.t(), Pad.name_t() | Pad.ref_t(), pad_props_t) ::
          LinkBuilder.t() | no_return
  def via_in(builder, pad, opts \\ [])

  def via_in(%LinkBuilder{status: :input}, pad, _opts) do
    raise ParentError,
          "Invalid link specification: output #{inspect(pad)} placed after another output"
  end

  def via_in(%LinkBuilder{} = builder, pad, props) do
    :ok = validate_pad_name(pad)
    :ok = validate_pad_props(props)

    LinkBuilder.update(builder, :input,
      input: pad,
      input_props: props
    )
  end

  @doc """
  Continues or ends a link.

  See the _links_ section of the moduledoc for more information.
  """
  @spec to(LinkBuilder.t(), Child.name_t()) :: LinkBuilder.t() | no_return
  def to(
        %LinkBuilder{
          links: [%{from: {Membrane.Bin, :itself}}, %{to: {Membrane.Bin, :itself}} | _] = links
        } = builder,
        child_name
      ) do
    to(%LinkBuilder{builder | links: tl(links)}, child_name)
  end

  def to(%LinkBuilder{links: [%{to: {Membrane.Bin, :itself}} | _]}, child_name) do
    raise ParentError,
          "Invalid link specification: child #{inspect(child_name)} placed after bin's output"
  end

  def to(%LinkBuilder{} = builder, child_name) do
    LinkBuilder.update(builder, :done, to: child_name)
  end

  @doc """
  Ends a link with a bin's output.

  See the _links_ section of the moduledoc for more information.
  """
  @spec to_bin_output(LinkBuilder.t(), Pad.name_t() | Pad.ref_t(), pad_props_t) ::
          LinkBuilder.t() | no_return
  def to_bin_output(builder, pad \\ :output, props \\ [])

  def to_bin_output(%LinkBuilder{status: :input}, pad, _props) do
    raise ParentError, "Invalid link specification: bin's output #{pad} placed after an input"
  end

  def to_bin_output(builder, pad, props) do
    builder |> via_in(pad, props) |> to({Membrane.Bin, :itself})
  end

  defp validate_pad_name(pad) when Pad.is_pad_name(pad) or Pad.is_pad_ref(pad) do
    :ok
  end

  defp validate_pad_name(pad) do
    raise ParentError, "Invalid link specification: invalid pad name: #{inspect(pad)}"
  end

  defp validate_pad_props(props) do
    unless Keyword.keyword?(props) do
      raise ParentError,
            "Invalid link specification: pad options should be a keyword, got: #{inspect(props)}"
    end

    props
    |> Keyword.keys()
    |> Enum.each(
      &unless &1 in @valid_pad_prop_keys do
        raise ParentError, "Invalid link specification: invalid pad option: #{inspect(&1)}"
      end
    )
  end
end
