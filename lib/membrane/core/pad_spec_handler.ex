defmodule Membrane.Core.PadSpecHandler do
  @moduledoc false
  # Module parsing pads specifications in elements.

  alias Membrane.{Core, Element, Pad}
  alias Core.PadModel
  alias Core.Element.State
  require Pad
  use Bunch
  use Core.Element.Log

  @doc """
  Initializes pads info basing on element's pads specifications.
  """
  @spec init_pads(State.t()) :: State.t()
  def init_pads(%State{module: module} = state) do
    pads = %{
      data: %{},
      info: module.membrane_pads() |> Bunch.KVList.map_values(&init_pad_info/1) |> Map.new(),
      dynamic_currently_linking: []
    }

    %State{state | pads: pads}
  end

  @spec init_pad_info(Pad.description_t()) :: PadModel.pad_info_t()
  defp init_pad_info(specs) do
    specs
    |> Bunch.Map.move!(:caps, :accepted_caps)
    |> Map.merge(
      case specs.availability |> Pad.availability_mode() do
        :dynamic -> %{current_id: 0}
        :static -> %{}
      end
    )
  end

  def add_bin_pads(module_pads) do
    Enum.flat_map(module_pads, &create_private_pad/1)
  end

  defp create_private_pad({_name, %{bin?: false}} = pad) do
    [pad]
  end

  defp create_private_pad({name, spec}) do
    priv_bin_name = Pad.create_private_name(name)

    public_spec = filter_opts(spec)

    priv_spec = filter_opts(%{spec | direction: opposite_direction(spec.direction)})

    [{name, public_spec}, {priv_bin_name, priv_spec}]
  end

  defp filter_opts(%{direction: :input} = spec), do: spec

  defp filter_opts(%{direction: :output} = spec),
    do: Map.drop(spec, @private_input_pad_spec_keys)

  # TODO to be replaced with Pad.opposite_direction/1 once merged to master!
  defp opposite_direction(:input), do: :output
  defp opposite_direction(:output), do: :input

end
