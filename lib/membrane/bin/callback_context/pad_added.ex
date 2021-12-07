defmodule Membrane.Bin.CallbackContext.PadAdded do
  @moduledoc """
  Structure representing a context that is passed to the bin
  when a new dynamic pad instance added is created
  """
  use Membrane.Core.Bin.CallbackContext,
    direction: :input | :output,
    options: map()
end
