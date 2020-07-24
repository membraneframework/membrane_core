defmodule Membrane.Pipeline.CallbackContext.SpecStarted do
  @moduledoc """
  Structure representing a context that is passed to the callback of the pipeline
  when it instantiates children and links them according to `Membrane.ParentSpec`
  """
  use Membrane.Core.Pipeline.CallbackContext
end
