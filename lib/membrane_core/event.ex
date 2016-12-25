defmodule Membrane.Event do
  @moduledoc """
  Structure representing a single event that flows between elements.

  Each event:

  - must contain type,
  - may contain payload.

  Type is used to distinguish event class.

  Payload can hold additional information about the event.

  Payload should always be a named struct appropriate for given event type.
  """

  @type type_t :: atom
  @type payload_t :: struct

  @type t :: %Membrane.Event{
    type: type_t,
    payload: payload_t
  }

  defstruct \
    type: nil,
    payload: nil


  @doc """
  Shorthand for creating a generic End of Stream event.

  End of Stream event means that all buffers from the stream were processed
  and no further buffers are expected to arrive.
  """
  @spec eos() :: t
  def eos() do
    %Membrane.Event{type: :eos}
  end


  @doc """
  Shorthand for creating a generic Discontinuity event.

  Discontinuity event means that flow of buffers in the stream was interrupted
  but stream itself is not done.

  Frequent reasons for this are soundcards' drops while capturing sound, network
  data loss etc.

  If duration of the discontinuity is known, it can be passed as an argument.

  See `Membrane.Event.Discontinuity.Payload` for the full description of the
  payload.
  """
  @spec discontinuity(Membrane.Event.Discontinuity.Payload.duration_t) :: t
  def discontinuity(duration \\ nil) do
    %Membrane.Event{type: :discontinuity, payload: %Membrane.Event.Discontinuity.Payload{duration: duration}}
  end
end
