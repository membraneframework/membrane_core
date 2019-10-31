defmodule Membrane.Bin.CallbackContext.PadAdded do
  @moduledoc """
  Structure representing a context that is passed to the bin when
  when new pad added is created
  """
  use Membrane.CallbackContext,
    direction: :input | :output,
    options: Keyword.t()
end
