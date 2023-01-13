defmodule Membrane.Pad do
  @moduledoc """
  Pads are units defined by elements and bins, allowing them to be linked with their
  siblings. This module consists of pads typespecs and utils.

  Each pad is described by its name, direction, availability, mode and possible stream format.
  For pads to be linkable, these properties have to be compatible. For more
  information on each of them, check appropriate type in this module.

  Each link can only consist of exactly two pads.
  """

  use Bunch

  alias Membrane.Buffer

  @availability_values [:always, :on_request]

  @typedoc """
  Defines the term by which the pad instance is identified.
  """
  @type ref_t :: name_t | {__MODULE__, name_t, dynamic_id_t}

  @typedoc """
  Possible id of dynamic pad
  """
  @type dynamic_id_t :: any

  @typedoc """
  Defines the name of pad or group of dynamic pads
  """
  @type name_t :: atom

  @typedoc """
  Defines possible pad directions:

  - `:output` - data can only be sent through such pad,
  - `:input` - data can only be received through such pad.

  One cannot link two pads with the same direction.
  """
  @type direction_t :: :output | :input

  @typedoc """
  Describes how an element sends and receives data.

  The available values for that field are:
  - `:manual` - meaning that the pad works in a pull mode and the demand is manually handled and requested.
  An element with output `:manual` pad can send data through such a pad only if it has already received demand
  on that pad. And element with input `:manual` pad receives data through such a pad only if it has been
  previously demanded, so that no undemanded data can arrive For more info, see `Membrane.Element.Action.demand_t`,
  `Membrane.Element.Action.redemand_t` and `c:Membrane.Element.WithOutputPads.handle_demand/5`.
  - `:auto` - meaning that the pad works in a pull mode and the demand is managed automatically:
  the core ensures that there's demand on each input pad (that has `flow_control` set to `:auto`)
  whenever there's demand on all output pads (that have `flow_control` set to `:auto`).
  Currently works only for `Membrane.Filter`s.
  - `:push` - meaning that the pad works in a push mode. An element with a `:push` output pad can send data
  through that pad whenever it wants. An element with a `:push` input pad has to deal with data whenever it
  comes through such a pad - note, that it needs to be done fast enough so that not to let data accumulate,
  what may lead to overflow of element process erlang queue, which is highly unwanted.

  Linking pads with different flow control is possible, but only in case of an output pad
  working in a push mode, and an input pad in pull mode (that is - with `:manual` or `:auto` flow control).
  In such case, however, an error will be raised whenever too many buffers accumulate on the input pad,
  waiting to be processed.
  """
  @type flow_control_t :: :auto | :manual | :push

  @typedoc """
  Values used when defining pad availability:

  - `:always` - a static pad, which can remain unlinked in `stopped` state only.
  - `:on_request` - a dynamic pad, instance of which is created every time it is
  linked to another pad. Thus linking the pad with _k_ other pads, creates _k_
  instances of the pad, and links each with another pad.
  """

  @type availability_t :: unquote(Bunch.Typespec.enum_to_alternative(@availability_values))

  @typedoc """
  Type describing availability mode of a created pad:

  - `:static` - there always exist exactly one instance of such pad.
  - `:dynamic` - multiple instances of such pad may be created and removed (which
  entails executing `handle_pad_added` and `handle_pad_removed` callbacks,
  respectively).
  """
  @type availability_mode_t :: :static | :dynamic

  @typedoc """
  Describes pattern, that should be matched by stream format send by element on specific
  pad. Will not be evaluated during runtime, but used for matching struct passed in
  `:stream_format` action.
  Can be a module name, pattern describing struct, or call to `any_of` function, which
  arguments are such patterns or modules names.
  If a module name is passed to the `:accepted_format` option or is passed to `any_of`,
  it will be converted to the match on a struct defined in that module, eg.
  `accepted_format: My.Format` will have this same effect, as `accepted_format: %My.Format{}`
  and `accepted_format: any_of(My.Format, %My.Another.Format{field: value} when value in
  [:some, :enumeration])` will have this same effect, as `accepted_format: any_of(%My.Format{},
  %My.Another.Format{field: value} when value in [:some, :enumeration])`
  """
  @type accepted_format_t :: module() | (pattern :: term())

  @typedoc """
  Describes how a pad should be declared in element or bin.
  """
  @type spec_t :: element_spec_t | bin_spec_t

  @typedoc """
  Describes how a pad should be declared inside a bin.

  Demand unit is derived from the first element inside the bin linked to the
  given input.
  """
  @type bin_spec_t ::
          {name_t(),
           availability: availability_t(),
           accepted_format: accepted_format_t(),
           options: Keyword.t()}

  @typedoc """
  Describes how a pad should be declared inside an element.
  """
  @type element_spec_t ::
          {name_t(),
           availability: availability_t(),
           accepted_format: accepted_format_t(),
           flow_control: flow_control_t(),
           options: Keyword.t(),
           demand_unit: Buffer.Metric.unit_t()}

  @typedoc """
  Type describing a pad. Contains data parsed from `t:spec_t/0`
  """
  @type description_t :: %{
          :availability => availability_t(),
          optional(:flow_control) => flow_control_t(),
          :name => name_t(),
          :accepted_formats_str => [String.t()],
          optional(:demand_unit) => Buffer.Metric.unit_t() | nil,
          :direction => direction_t(),
          :options => nil | Keyword.t()
        }

  @doc """
  Creates a static pad reference.
  """
  defmacro ref(name) do
    quote do
      unquote(name)
    end
  end

  @doc """
  Creates a dynamic pad reference.
  """
  defmacro ref(name, id) do
    quote do
      {unquote(__MODULE__), unquote(name), unquote(id)}
    end
  end

  defguard is_pad_ref(term)
           when term |> is_atom or
                  (term |> is_tuple and term |> tuple_size == 3 and term |> elem(0) == __MODULE__ and
                     term |> elem(1) |> is_atom)

  defguard is_pad_name(term) when is_atom(term)

  defguard is_availability(term) when term in @availability_values

  defguard is_availability_dynamic(availability) when availability == :on_request
  defguard is_availability_static(availability) when availability == :always

  @doc """
  Returns pad availability mode for given availability.
  """
  @spec availability_mode(availability_t) :: availability_mode_t
  def availability_mode(:always), do: :static
  def availability_mode(:on_request), do: :dynamic

  @doc """
  Returns the name for the given pad reference
  """
  @spec name_by_ref(ref_t()) :: name_t()
  def name_by_ref(ref(name, _id)) when is_pad_name(name), do: name
  def name_by_ref(name) when is_pad_name(name), do: name

  @spec opposite_direction(direction_t()) :: direction_t()
  def opposite_direction(:input), do: :output
  def opposite_direction(:output), do: :input
end
