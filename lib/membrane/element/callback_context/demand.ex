defmodule Membrane.Element.CallbackContext.Demand do
  @moduledoc """
  Structure representing a context that is passed to the element
  when processing incoming demand.
  """
  use Membrane.CallbackContext,
    incoming_demand: non_neg_integer()
end
