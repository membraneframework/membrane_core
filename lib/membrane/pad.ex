defmodule Membrane.Pad do
  @moduledoc """
  Pads are units defined by each element, allowing it to be linked with another
  elements. This module consists of pads typespecs and utils.

  Each pad is described by its name, direction, availability, mode and possible caps.
  For pads to be linkable, these properties have to be compatible. For more
  information on each of them, check appropriate type in this module.

  Each link can only consist of exactly two pads.
  """

  alias Membrane.{Buffer, Caps}
  use Bunch
  use Bunch.Typespec

  @typedoc """
  Defines the term by which the pad instance is identified.
  """
  @type ref_t :: name_t | {:dynamic, name_t, dynamic_id_t}

  @typedoc """
  Possible id of dynamic pad
  """
  @type dynamic_id_t :: non_neg_integer

  @typedoc """
  Defines the name of pad or group of dynamic pads
  """
  @type name_t :: atom | {:private, atom}

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
  already received demand on the pad. Sending small, limited amount of
  undemanded data is supported and handled by `Membrane.Core.InputBuffer`.
  - `:pull` input pad - element receives through such pad only data that it has
  previously demanded, so that no undemanded data can arrive.

  Linking pads with different modes is possible, but only in case of output pad
  working in push mode, and input in pull mode. Moreover, toilet mode of
  `Membrane.Core.InputBuffer` has to be enabled then.

  For more information on transfering data and demands, see `Membrane.Source`,
  `Membrane.Filter`, `Membrane.Sink`.
  """
  @type mode_t :: :push | :pull

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
  The only difference is that `:demand_unit` option specified in
  bin will be used to make demands from bin's elements connected
  to its input pad.
  """
  @type bin_spec_t :: input_spec_t

  @typedoc """
  Describes how an output pad should be declared inside an element.
  """
  @type output_spec_t :: {name_t(), [common_spec_options_t]}

  @typedoc """
  Describes how an input pad should be declared inside an element.
  """
  @type input_spec_t ::
          {name_t(), [common_spec_options_t | {:demand_unit, Buffer.Metric.unit_t()}]}

  @typedoc """
  Pad options used in `t:spec_t/0`
  """
  @type common_spec_options_t ::
          {:availability, availability_t()}
          | {:mode, mode_t()}
          | {:caps, Caps.Matcher.caps_specs_t()}
          | {:options, Keyword.t()}

  @typedoc """
  Type describing a pad. Contains data parsed from `t:spec_t/0`
  """
  @type description_t :: %{
          :availability => availability_t(),
          :mode => mode_t(),
          :caps => Caps.Matcher.caps_specs_t(),
          optional(:demand_unit) => Buffer.Metric.unit_t(),
          :direction => direction_t(),
          :options => nil | Keyword.t(),
          :bin? => boolean()
        }

  defguard is_pad_ref(term)
           when term |> is_atom or
                  (term |> is_tuple and term |> tuple_size == 3 and term |> elem(0) == :dynamic and
                     term |> elem(1) |> is_atom and term |> elem(2) |> is_integer)

  defguardp is_public_name(term) when is_atom(term)

  defguardp is_private_name(term)
            when tuple_size(term) == 2 and elem(term, 0) == :private and is_atom(elem(term, 1))

  defguard is_pad_name(term)
           when is_public_name(term) or is_private_name(term)

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
  def name_by_ref({:dynamic, name, _id}) when is_pad_name(name), do: name
  def name_by_ref(ref) when is_pad_name(ref), do: ref

  @spec opposite_direction(direction_t()) :: direction_t()
  def opposite_direction(:input), do: :output
  def opposite_direction(:output), do: :input

  @spec get_corresponding_bin_pad(ref_t()) :: ref_t()
  def get_corresponding_bin_pad({:dynamic, name, id}),
    do: {:dynamic, get_corresponding_bin_name(name), id}

  def get_corresponding_bin_pad(name), do: get_corresponding_bin_name(name)

  @spec create_private_name(atom) :: name_t()
  def create_private_name(name) when is_public_name(name) do
    get_corresponding_bin_name(name)
  end

  @spec get_corresponding_bin_name(name_t()) :: name_t()
  defp get_corresponding_bin_name({:private, name}) when is_public_name(name), do: name
  defp get_corresponding_bin_name(name) when is_public_name(name), do: {:private, name}

  def assert_public_name!(name) when is_public_name(name) do
    :ok
  end

  def assert_public_name!(name) do
    raise CompileError,
      file: __ENV__.file,
      description: "#{inspect(name)} is not a proper pad name. Use public names only."
  end
end
