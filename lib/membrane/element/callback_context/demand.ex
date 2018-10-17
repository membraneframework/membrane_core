defmodule Membrane.Element.CallbackContext.Demand do
  @moduledoc """
  Structure representing a context that is passed to the element
  when processing incoming demand.
  """
  use Membrane.Element.CallbackContext,
    caps: Membrane.Caps.t(),
    incoming_demand: non_neg_integer()
end
