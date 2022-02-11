defmodule Membrane.Element.CallbackContext.Write do
  @moduledoc """
  Structure representing a context that is passed to the element
  when new buffer arrives to the sink or the endpoint.
  """
  use Membrane.Core.Element.CallbackContext
end
