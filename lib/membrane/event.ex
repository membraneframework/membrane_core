defmodule Membrane.Event do
  @moduledoc """
  Event is an entity that can be sent between elements.

  Events can flow either downstream or upstream - they can be sent with
  `t:Membrane.Element.Action.event_t/0`, and can be handled in
  `c:Membrane.Element.Base.handle_event/4`. Each event is
  to implement `Membrane.EventProtocol`, which allows to configure its behaviour.
  """

  alias Membrane.EventProtocol

  @type t :: EventProtocol.t()

  @spec event?(t()) :: boolean
  def event?(event) do
    EventProtocol.impl_for(event) != nil
  end

  defdelegate sticky?(event), to: EventProtocol

  defdelegate async?(event), to: EventProtocol
end
