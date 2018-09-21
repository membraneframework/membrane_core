defprotocol Membrane.EventProtocol do
  @moduledoc """
  Protocol that allows to configure behaviour of `Membrane.Event`s.

  Each event has to implement or derive this protocol.
  """

  @type t :: struct

  @doc """
  Specifies whether event is sent right away (not sticky), or it is 'pushed' by
  the next sent buffer (sticky). Defaults to false (not sticky).

  Returning a sticky event from a callback stores it in a queue. When the next
  buffer is to be sent, all events from the queue are sent before it. An example
  can be the `Membrane.Event.StartOfStream` event.
  """
  @spec sticky?(t) :: boolean
  def sticky?(_event)

  @doc """
  Determines whether event is synchronized with buffers. Defaults to true.

  Buffers and synchronized events are always received in the same order they are
  sent. Non-synchronized events skip buffers waiting in internal buffers
  (such as `Membrane.PullBuffer`) and are handled first. In other words,
  they have priority over buffers.
  """
  @spec synchronized?(t) :: boolean
  def synchronized?(_event)
end

defmodule Membrane.EventProtocol.DefaultImpl do
  @moduledoc """
  Default implementation of `Membrane.EventProtocol`.

  If `use`d in `defimpl`, not implemented callbacks fallback to default ones.
  """
  defmacro __using__(_args) do
    quote do
      @impl true
      def sticky?(_event), do: false

      @impl true
      def synchronized?(_event), do: true

      defoverridable synchronized?: 1, sticky?: 1
    end
  end
end

defimpl Membrane.EventProtocol, for: Any do
  use Membrane.EventProtocol.DefaultImpl
end
