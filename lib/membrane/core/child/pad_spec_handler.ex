defmodule Membrane.Core.Child.PadSpecHandler do
  @moduledoc false

  # Module parsing pads specifications in elements and bins.

  use Bunch

  alias Membrane.Core.{Bin, Child, Element}
  alias Membrane.Pad

  require Membrane.Pad

  @doc """
  Initializes pads info basing on element's or bin's pads specifications.
  """
  @spec init_pads(Element.State.t()) :: Element.State.t()
  @spec init_pads(Bin.State.t()) :: Bin.State.t()
  def init_pads(state) do
    %{
      state
      | pads_info:
          get_pads(state)
          |> Map.new(),
        pads_data: %{}
    }
  end

  @spec get_pads(Child.state_t()) :: [{Pad.name_t(), Pad.description_t()}]
  def get_pads(%Bin.State{module: module}) do
    module.membrane_pads()
  end

  def get_pads(%Element.State{module: module}) do
    module.membrane_pads()
  end
end
