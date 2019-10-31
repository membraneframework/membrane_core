defmodule Membrane.Bin.CallbackContext.PadRemoved do
  @moduledoc """
  Structure representing a context that is passed to the bin
  when pad is removed
  """
  use Membrane.CallbackContext,
    direction: :input | :output
end
