defmodule Membrane.Bin.CallbackContext.PadAdded do
  @moduledoc """
  Structure representing a context that is passed to the bin when
  when a new dynamic pad instance added is created
  """
  use Membrane.Bin.CallbackContext,
    direction: :input | :output,
    options: Keyword.t()
end
