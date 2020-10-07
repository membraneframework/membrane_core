defmodule Membrane.Core.Child.PadSpecHandler do
  @moduledoc false

  # Module parsing pads specifications in elements and bins.

  use Bunch

  alias Membrane.Core.{Bin, Child, Element}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Pad

  require Membrane.Pad

  @private_input_pad_spec_keys [:demand_unit]

  @doc """
  Initializes pads info basing on element's or bin's pads specifications.
  """
  @spec init_pads(Element.State.t()) :: Element.State.t()
  @spec init_pads(Bin.State.t()) :: Bin.State.t()
  def init_pads(state) do
    pads = %{
      data: %{},
      info:
        get_pads(state)
        |> Bunch.KVList.map_values(&init_pad_info/1)
        |> Map.new(),
      dynamic_currently_linking: []
    }

    state
    |> Map.put(:pads, pads)
  end

  @spec init_pad_info(Pad.description_t()) :: PadModel.pad_info_t()
  defp init_pad_info(specs) do
    specs |> Bunch.Map.move!(:caps, :accepted_caps)
  end

  @spec get_pads(Child.state_t()) :: [{Pad.name_t(), Pad.description_t()}]
  def get_pads(%Bin.State{module: module}) do
    Enum.flat_map(module.membrane_pads(), &process_bin_pad/1)
  end

  def get_pads(%Element.State{module: module}) do
    module.membrane_pads()
  end

  defp process_bin_pad({name, spec}) do
    priv_bin_name = Pad.create_private_name(name)
    public_spec = filter_bin_pad_opts(spec)

    priv_spec =
      filter_bin_pad_opts(%{spec | direction: Pad.opposite_direction(spec.direction), options: []})

    [{name, public_spec}, {priv_bin_name, priv_spec}]
  end

  defp filter_bin_pad_opts(%{direction: :input} = spec), do: spec

  defp filter_bin_pad_opts(%{direction: :output} = spec),
    do: Map.drop(spec, @private_input_pad_spec_keys)
end
