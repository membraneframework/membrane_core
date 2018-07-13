defmodule Membrane.Message do
  @moduledoc """
  Structure representing a single message that is emitted by the element.

  Each message:

  - must contain type,
  - may contain payload.

  Type is used to distinguish message class.

  Payload can hold additional information about the message.

  Payload should always be a named struct appropriate for given message type.
  """

  @type type_t :: atom
  @type payload_t :: struct

  @type t :: %Membrane.Message{
          type: type_t,
          payload: payload_t
        }

  defstruct type: nil,
            payload: nil
end
