defmodule Membrane.Core.Element.PadSpecHandler do
  @moduledoc false
  # Module parsing pads specifications in elements.

  alias Membrane.{Core, Element}
  alias Element.Pad
  alias Core.Element.{PadModel, State}
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
      info: module.membrane_pads() |> Bunch.TupleList.map_values(&init_pad_info/1) |> Map.new(),
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
end
