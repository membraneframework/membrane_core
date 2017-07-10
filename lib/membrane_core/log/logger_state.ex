defmodule Membrane.Log.Logger.State do
  @moduledoc false
  # Structure representing state of the logger. It is a part of the private API.
  # It does not represent state of logger you construct, it's a state used
  # internally in Membrane.

  @type t :: %Membrane.Log.Logger.State{
    internal_state: any,
    module: module,
  }

  defstruct \
    internal_state: nil,
    module: nil

  @doc """
  Returns new state and initializes it with given `module` and `internal_state`.

  This function always returns Membrane.Logger.State struct.
  """
  @spec new(module, any) :: t
  def new(module, internal_state) do
    %Membrane.Log.Logger.State{module: module, internal_state: internal_state}
  end

end
