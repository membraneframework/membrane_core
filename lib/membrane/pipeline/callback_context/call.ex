defmodule Membrane.Pipeline.CallbackContext.Call do
  @moduledoc """
  Structure representing a context that is passed to the callback when the
  pipeline is called with a synchronous call.
  """
  use Membrane.Core.Pipeline.CallbackContext,
    from: [GenServer.from()]
end
