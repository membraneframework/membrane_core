defmodule Membrane.Bin.CallbackContext.SpecStarted do
  @moduledoc """
  Structure representing a context that is passed to the callback of the bin
  when it instantiates children and links them according to `Membrane.ChildrenSpec`
  """
  use Membrane.Core.Bin.CallbackContext
end
