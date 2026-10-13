defmodule Membrane.Core.Element.BufferBatcher do
  @moduledoc false

  # Module responsible for batching the outgoing buffers into as few messages as possible.
  #
  # When an element handles many buffers in a row (e.g. a message with 100 buffers arrives
  # on a push pad, or 100 buffers are popped from the input queue at once), `handle_buffer`
  # is executed once per each buffer. If each of these callbacks returns a `:buffer` action,
  # sending the buffers one by one would result in 100 messages, while one message with
  # 100 buffers would suffice.
  #
  # Instead of being sent right away, buffers returned in `:buffer` actions are stored in
  # the batch kept in `State.buffer_batch`. The batch holds buffers for a single output pad
  # and is flushed, i.e. sent in a single message, when:
  #   - `Membrane.Core.Element.ActionHandler` handles any action other than `:buffer`, so that
  #     the order of actions is preserved. Actions that merely expand to other actions
  #     (`:split`, `:forward`, `:broadcast`) don't flush the batch themselves, as the actions
  #     they expand to are handled as usual,
  #   - a `:buffer` action targets another output pad, so that buffers sent through different
  #     pads are never reordered,
  #   - `Membrane.Core.Element.EffectiveFlowController` is about to send a message through
  #     the output pads, so that the order of messages received by the next element is preserved,
  #   - `Membrane.Core.Element` finishes handling a message, so that buffers are never delayed
  #     until the next message arrives.
  #
  # Everything apart from the actual send (demand bookkeeping, telemetry, metrics, validation)
  # is still performed when the `:buffer` action is handled, so batching is not observable
  # from the element's perspective.

  alias Membrane.Buffer
  alias Membrane.Core.Element.State
  alias Membrane.Core.Message
  alias Membrane.Pad

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Logger

  @type t :: %{
          pad_ref: Pad.ref(),
          pid: pid(),
          other_ref: Pad.ref(),
          reversed_buffers: [Buffer.t()]
        }

  @doc """
  Stores buffers to be sent through `pad_ref`.
  """
  @spec store(Pad.ref(), [Buffer.t()], State.t()) :: State.t()
  def store(pad_ref, buffers, %State{buffer_batch: nil} = state) do
    %{pid: pid, other_ref: other_ref} = PadModel.get_data!(state, pad_ref)

    batch = %{
      pad_ref: pad_ref,
      pid: pid,
      other_ref: other_ref,
      reversed_buffers: Enum.reverse(buffers)
    }

    %{state | buffer_batch: batch}
  end

  def store(pad_ref, buffers, %State{buffer_batch: %{pad_ref: pad_ref} = batch} = state) do
    batch = %{batch | reversed_buffers: Enum.reverse(buffers, batch.reversed_buffers)}
    %{state | buffer_batch: batch}
  end

  def store(pad_ref, buffers, %State{} = state) do
    store(pad_ref, buffers, flush(state))
  end

  @doc """
  Sends all the stored buffers in a single message.
  """
  @spec flush(State.t()) :: State.t()
  def flush(%State{buffer_batch: nil} = state), do: state

  def flush(%State{buffer_batch: batch} = state) do
    %{pad_ref: pad_ref, pid: pid, other_ref: other_ref, reversed_buffers: reversed_buffers} =
      batch

    buffers = Enum.reverse(reversed_buffers)

    Membrane.Logger.debug_verbose(
      "Sending #{length(buffers)} buffer(s) through pad #{inspect(pad_ref)}"
    )

    Message.send(pid, :buffer, buffers, for_pad: other_ref)
    %{state | buffer_batch: nil}
  end
end
