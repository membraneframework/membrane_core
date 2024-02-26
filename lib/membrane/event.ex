defmodule Membrane.Event do
  @moduledoc """
  Represents a communication event, capable of flowing both downstream and upstream.

  Events are dispatched using `t:Membrane.Element.Action.event/0` and are handled via the
  `c:Membrane.Element.Base.handle_event/4` callback. Each event must conform to the
  `Membrane.EventProtocol` to ensure the proper configuration of its behaviour.
  """

  alias Membrane.EventProtocol

  @typedoc """
  The Membrane event, based on the `Membrane.EventProtocol`.
  """
  @type t :: EventProtocol.t()

  @doc """
  Checks if the given argument is a Membrane event.

  Returns `true` if the `event` implements the `Membrane.EventProtocol`, otherwise `false`.
  """
  @spec event?(t()) :: boolean
  def event?(event) do
    EventProtocol.impl_for(event) != nil
  end

  defdelegate sticky?(event), to: EventProtocol

  defdelegate async?(event), to: EventProtocol
end
