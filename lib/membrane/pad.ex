defmodule Membrane.Pad do
  @moduledoc """
  Pads are units defined by elements and bins, allowing them to be linked with their
  siblings. This module consists of pads typespecs and utils.

  Each pad is described by its name, direction, availability, mode and possible caps.
  For pads to be linkable, these properties have to be compatible. For more
  information on each of them, check appropriate type in this module.

  Each link can only consist of exactly two pads.
  """

  use Bunch
  use Bunch.Typespec

  alias Membrane.Buffer

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
  Modes are strictly related to pad directions:

  - `:push` output pad - element can send data through such pad whenever it wants.
  - `:push` input pad - element has to deal with data whenever it comes through
  such pad, and do it fast enough not to let data accumulate on such pad, what
  may lead to overflow of element process erlang queue, which is highly unwanted.
  - `:pull` output pad - element can send data through such pad only if it have
  already received demand on the pad.
  - `:pull` input pad - element receives through such pad only data that it has
  previously demanded, so that no undemanded data can arrive.

  Linking pads with different modes is possible, but only in case of output pad
  working in push mode, and input in pull mode. In such case, however, error will
  be raised whenever too many buffers accumulate on the input pad, waiting to be
  processed.

  For more information on transfering data and demands, see `t:demand_mode_t/0`,
  `Membrane.Source`, `Membrane.Filter`, `Membrane.Endpoint`, `Membrane.Sink`.
  """
  @type mode_t :: :push | :pull

  @typedoc """
  Defines the mode of handling and requesting demand on pads.

  - `:manual` - demand is manually handled and requested. See `Membrane.Element.Action.demand_t`,
  `Membrane.Element.Action.redemand_t`, `c:Membrane.Element.WithOutputPads.handle_demand/5`
  - `:auto` - demand is managed automatically: the core ensures that there's demand
  on each input pad (that has `demand_mode` set to `:auto`) whenever there's demand on all
  output pads (that have `demand_mode` set to `:auto`). Currently works only for
  `Membrane.Filter`s.
  """
  @type demand_mode_t :: :manual | :auto

  @typedoc """
  Values used when defining pad availability:

  - `:always` - a static pad, which can remain unlinked in `stopped` state only.
  - `:on_request` - a dynamic pad, instance of which is created every time it is
  linked to another pad. Thus linking the pad with _k_ other pads, creates _k_
  instances of the pad, and links each with another pad.
  """
  @list_type availability_t :: [:always, :on_request]

  @typedoc """
  Type describing availability mode of a created pad:

  - `:static` - there always exist exactly one instance of such pad.
  - `:dynamic` - multiple instances of such pad may be created and removed (which
  entails executing `handle_pad_added` and `handle_pad_removed` callbacks,
  respectively).
  """
  @type availability_mode_t :: :static | :dynamic

  @typedoc """
  Describes how a pad should be declared in element or bin.
  """
  @type spec_t :: output_spec_t | input_spec_t | bin_spec_t

  @typedoc """
  For bins there are exactly the same options for both directions.
  Demand unit is derived from the first element inside the bin linked to the
  given input.
  """
  @type bin_spec_t :: {name_t(), [common_spec_options_t]}

  @typedoc """
  Describes how an output pad should be declared inside an element.
  """
  @type output_spec_t :: {name_t(), [common_spec_options_t | {:demand_mode, demand_mode_t()}]}

  @typedoc """
  Describes how an input pad should be declared inside an element.
  """
  @type input_spec_t ::
          {name_t(),
           [
             common_spec_options_t
             | {:demand_mode, demand_mode_t()}
             | {:demand_unit, Buffer.Metric.unit_t()}
           ]}

  @typedoc """
  Pad options used in `t:spec_t/0`
  """
  @type common_spec_options_t ::
          {:availability, availability_t()}
          | {:mode, mode_t()}
          | {:options, Keyword.t()}

  @typedoc """
  Type describing a pad. Contains data parsed from `t:spec_t/0`
  """
  @type description_t :: %{
          :availability => availability_t(),
          :mode => mode_t(),
          :name => name_t(),
          optional(:demand_unit) => Buffer.Metric.unit_t(),
          :direction => direction_t(),
          :options => nil | Keyword.t(),
          optional(:demand_mode) => demand_mode_t()
        }

  @typedoc """
  Type describing module with a name of a pad defined in it.
  """
  @type module_with_pad_t() :: {module(), name_t()}

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

  defguard is_availability(term) when term in @availability_t

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
