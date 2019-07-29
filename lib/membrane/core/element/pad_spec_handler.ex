defmodule Membrane.Core.Element.PadSpecHandler do
  @moduledoc false
  # Module parsing pads specifications in elements.

  alias Membrane.Bin
  alias Membrane.{Core, Element}
  alias Element.Pad
  alias Core.Element
  alias Core.Element.{PadModel}
  require Pad
  use Bunch
  use Core.Element.Log

  @doc """
  Initializes pads info basing on element's pads specifications.
  """
  @spec init_pads(Element.State.t() | Bin.State.t()) :: State.t()
  def init_pads(%Element.State{module: module} = state) do
    pads = %{
      data: %{},
      info: module.membrane_pads() |> Bunch.KVList.map_values(&init_pad_info/1) |> Map.new(),
      dynamic_currently_linking: []
    }

    %Element.State{state | pads: pads}
  end

  def init_pads(%Bin.State{module: module} = state) do
    pads = %{
      data: %{},
      info: module.membrane_pads() |> Bunch.KVList.map_values(&init_pad_info/1) |> Map.new(),
      dynamic_currently_linking: []
    }

    %Bin.State{state | pads: pads}
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
end
