defmodule Membrane.ParentSpec do
  @moduledoc """
  Structure representing topology of a pipeline/bin.
  It can be returned from
  `c:Membrane.Pipeline.handle_init/1` and `c:Membrane.Bin.handle_init/1` callback upon initialization.
  It will define a topology of children and links that build the pipeline/bin.

  ## Children

  Children that should be spawned when the pipeline/bin starts can be defined
  with the `:children` field.
  You have to set it to a map, where keys are valid children names (`t:Membrane.Child.name_t/0`)
  that are unique within this pipeline/bin and values are either element's module or
  struct of that module.

  Sample definitions:

      %{
        first_element: %Element.With.Options.Struct{option_a: 42},
        some_element: Element.Without.Options,
        other_element: Bin.Using.Default.Options
      }

  ## Links

  Links that should be made when the pipeline starts, and children are spawned
  can be defined with the `:links` field. Links can be defined with use of
  `link/1` and `to/2` functions that allow to specify elements linked, and
  `via_in/2` and `via_out/2` that allow to specify pads' names and options. If pads
  are not specified, name `:input` is assumed for inputs and `:output` for outputs.

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

  require Membrane.Pad

  alias Membrane.{Child, Element, Pad}
  alias Membrane.Core.InputBuffer
  alias Membrane.ParentError

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
          [{Membrane.Element.name_t(), child_spec_t}]
          | %{Membrane.Element.name_t() => child_spec_t}

  @typedoc """
  Options passed to the element when linking its pad with a different one.

  The allowed options are:
  * `id` - id of dynamic pad instance. Valid only for dynamic pads.
  * `:buffer` - keyword allowing to configure `Membrane.Core.InputBuffer` between elements. Valid only for input pads.
    See `t:Membrane.Core.InputBuffer.props_t/0` for configurable properties.
  * `:pad` - any element-specific options that will be available in `Membrane.Pad.Data` struct.
  """
  @type pad_options_t :: [
          {:id, Pad.dynamic_id_t()}
          | {:buffer, InputBuffer.props_t()}
          | {:pad, element_specific_opts :: any()}
        ]

  @type links_spec_t :: [LinkBuilder.t() | links_spec_t]

  @typedoc """
  Struct used when starting elements within a pipeline or a bin.
  """
  @type t :: %__MODULE__{
          children: children_spec_t,
          links: links_spec_t,
          stream_sync: :sinks | [[Element.name_t()]],
          clock_provider: Element.name_t()
        }

  @valid_link_opt_keys [:id, :pad, :buffer]

  defstruct children: %{},
            links: [],
            stream_sync: [],
            clock_provider: nil

  @spec link(Child.name_t()) :: LinkBuilder.t()
  def link(child_name) do
    %LinkBuilder{links: [%{from: child_name}], status: :from}
  end

  @spec link_bin_input(Pad.name_t(), pad_options_t) :: LinkBuilder.t() | no_return
  def link_bin_input(pad \\ :input, opts \\ []) do
    %LinkBuilder{links: [%{from: {Membrane.Bin, :itself}}], status: :from} |> via_out(pad, opts)
  end

  @spec via_out(LinkBuilder.t(), Pad.name_t(), pad_options_t) :: LinkBuilder.t() | no_return
  def via_out(builder, pad, opts \\ [])

  def via_out(%LinkBuilder{status: :output}, pad, _opts) do
    raise ParentError,
          "Invalid link specification: output #{inspect(pad)} placed after another output or bin's input"
  end

  def via_out(%LinkBuilder{status: :input}, pad, _opts) do
    raise ParentError, "Invalid link specification: output #{inspect(pad)} placed after an input"
  end

  def via_out(%LinkBuilder{} = builder, pad, opts) do
    :ok = validate_pad_name(pad)
    :ok = validate_pad_opts(opts)
    {id, opts} = opts |> Keyword.pop(:id)

    LinkBuilder.update(builder, :output,
      output: pad,
      output_id: id,
      output_opts: opts
    )
  end

  @spec via_in(LinkBuilder.t(), Pad.name_t(), pad_options_t) :: LinkBuilder.t() | no_return
  def via_in(builder, pad, opts \\ [])

  def via_in(%LinkBuilder{status: :input}, pad, _opts) do
    raise ParentError,
          "Invalid link specification: output #{inspect(pad)} placed after another output"
  end

  def via_in(%LinkBuilder{} = builder, pad, opts) do
    :ok = validate_pad_name(pad)
    :ok = validate_pad_opts(opts)
    {id, opts} = opts |> Keyword.pop(:id)

    LinkBuilder.update(builder, :input,
      input: pad,
      input_id: id,
      input_opts: opts
    )
  end

  @spec to(LinkBuilder.t(), Child.name_t()) :: LinkBuilder.t()
  def to(%LinkBuilder{} = builder, child_name) do
    LinkBuilder.update(builder, :done, to: child_name)
  end

  @spec to_bin_output(LinkBuilder.t(), Pad.name_t(), pad_options_t) :: LinkBuilder.t() | no_return
  def to_bin_output(builder, pad \\ :output, opts \\ [])

  def to_bin_output(%LinkBuilder{status: :input}, pad, _opts) do
    raise ParentError, "Invalid link specification: bin's output #{pad} placed after an input"
  end

  def to_bin_output(builder, pad, opts) do
    builder |> via_in(pad, opts) |> LinkBuilder.update(:done, to: {Membrane.Bin, :itself})
  end

  defp validate_pad_name(pad) when Pad.is_pad_name(pad) do
    :ok
  end

  defp validate_pad_name(pad) do
    raise ParentError, "Invalid link specification: invalid pad name: #{inspect(pad)}"
  end

  defp validate_pad_opts(opts) do
    unless Keyword.keyword?(opts) do
      raise ParentError,
            "Invalid link specification: pad options should be a keyword, got: #{inspect(opts)}"
    end

    opts
    |> Keyword.keys()
    |> Enum.each(
      &unless &1 in @valid_link_opt_keys do
        raise ParentError, "Invalid link specification: invalid pad option: #{inspect(&1)}"
      end
    )
  end
end
