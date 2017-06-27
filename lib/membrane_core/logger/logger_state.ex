defmodule Membrane.Logger.State do
  @moduledoc false
  # Structure representing state of the logger. It is a part of the private API.
  # It does not represent state of logger you construct, it's a state used
  # internally in Membrane.

  @type t :: %Membrane.Logger.State{
    internal_state: any,
    module: module,
  }

  defstruct \
    internal_state: nil,
    module: nil


  @spec new(module, any) :: t
  def new(module, internal_state) do
    %Membrane.Logger.State{module: module, internal_state: internal_state}
  end

end
