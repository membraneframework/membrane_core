defmodule Membrane.Bin.CallbackContext.PadRemoved do
  @moduledoc """
  Structure representing a context that is passed to the bin
  when a dynamic pad is removed
  """
  use Membrane.Core.Bin.CallbackContext,
    direction: :input | :output
end
