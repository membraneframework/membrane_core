defmodule Membrane.Element.CallbackContext do
  @moduledoc """
  Parent module for all contexts passed to callbacks
  """

  @macrocallback from_state(Membrane.Core.Element.State.t(), keyword()) :: Macro.t()
end
