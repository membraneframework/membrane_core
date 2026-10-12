defmodule Membrane.Core.Element.BufferBatcher do
  @moduledoc false

  # Module responsible for batching outgoing buffers into as few messages as possible.
  #
  # When an element handles many buffers in a row (e.g. a message with 100 buffers arrives
  # on a push pad, or 100 buffers are popped from the input queue at once), `handle_buffer`
  # is executed once per each buffer. If each of these callbacks returns a `:buffer` action,
  # sending each of them separately would result in 100 messages, where one message with
  # 100 buffers would suffice.
  #
  # Instead of sending buffers right away, `:buffer` actions store them in the batch kept
  # in `State.buffer_batch`. Subsequent `:buffer` actions targeting the same output pad
  # are appended to the batch. The batch is flushed (sent as a single message) when:
  #   - any action other than `:buffer` is handled (so that the order of actions is preserved),
  #   - a `:buffer` action targeting another output pad is handled (so that buffers sent through
  #     different pads are never reordered),
  #   - the element finishes handling a message (so that the buffers are never delayed until
  #     the next message arrives).
  #
  # Note that everything apart from the actual `send/2` (demand bookkeeping, telemetry, metrics,
  # validation) is still performed when the action is handled, so storing buffers in the batch
  # is not observable from the element's perspective.

  alias Membrane.Buffer
  alias Membrane.Core.Element.State
  alias Membrane.Pad

  alias Membrane.Core.Message
  require Membrane.Logger

  @type t :: %{
          pad_ref: Pad.ref(),
          pid: pid(),
          other_ref: Pad.ref(),
          # buffers are stored in reversed order
          buffers: [Buffer.t()]
        }

  @doc """
  Stores buffers to be sent via `pad_ref`. If the batch already contains buffers
  for another pad, it is flushed first.
  """
  @spec store(Pad.ref(), pid(), Pad.ref(), [Buffer.t()], State.t()) :: State.t()
  def store(pad_ref, pid, other_ref, buffers, %State{} = state) do
    case state.buffer_batch do
      %{pad_ref: ^pad_ref, buffers: batched_buffers} = batch ->
        batch = %{batch | buffers: Enum.reverse(buffers, batched_buffers)}
        %{state | buffer_batch: batch}

      nil ->
        batch = %{
          pad_ref: pad_ref,
          pid: pid,
          other_ref: other_ref,
          buffers: Enum.reverse(buffers)
        }

        %{state | buffer_batch: batch}

      _other_pad_batch ->
        store(pad_ref, pid, other_ref, buffers, flush(state))
    end
  end

  @doc """
  Sends all the batched buffers (if any) in a single message.
  """
  @spec flush(State.t()) :: State.t()
  def flush(%State{buffer_batch: nil} = state), do: state

  def flush(%State{buffer_batch: batch} = state) do
    %{pad_ref: pad_ref, pid: pid, other_ref: other_ref, buffers: buffers} = batch
    buffers = Enum.reverse(buffers)

    Membrane.Logger.debug_verbose(
      "Sending #{length(buffers)} buffer(s) through pad #{inspect(pad_ref)}"
    )

    Message.send(pid, :buffer, buffers, for_pad: other_ref)
    %{state | buffer_batch: nil}
  end
end
