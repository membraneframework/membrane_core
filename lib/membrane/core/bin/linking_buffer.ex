defmodule Membrane.Core.Bin.LinkingBuffer do
  @moduledoc false

  alias Membrane.Core.Bin.State
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Message
  alias Membrane.Pad

  require Membrane.Logger
  require Message
  require Pad

  @type t :: %{Pad.name_t() => [Message.t()]}

  @doc """
  Creates a new linking buffer.
  """
  @spec new :: t()
  def new, do: Map.new()

  @doc """
  This function sends a message to pad, IF AND ONLY IF
  this pad is already linked. If it's not, it is stored
  and will be sent after calling `flush_for_pad()`.
  Params:
  * buf - buffer structure
  * msg - message to be sent
  * sender_pad - pad from which the message is supposed
                   to be sent
  * bin_state - state of the bin
  """
  @spec store_or_send(Message.t(), Pad.ref_t(), State.t()) :: State.t()
  def store_or_send(msg, sender_pad, bin_state) do
    buf = bin_state.linking_buffer

    with {:ok, %{pid: dest_pid, other_ref: other_ref}} <-
           PadModel.get_data(bin_state, sender_pad),
         false <- currently_linking?(sender_pad, bin_state) do
      send(dest_pid, Message.set_for_pad(msg, other_ref))
      bin_state
    else
      _unknown_or_linking ->
        new_buf = Map.update(buf, sender_pad, [msg], &[msg | &1])
        %{bin_state | linking_buffer: new_buf}
    end
  end

  defp currently_linking?(pad, state),
    do: pad in state.pads.dynamic_currently_linking

  @doc """
  Sends messages stored for a given output pad.
  A link must already be available.
  """
  @spec flush_for_pad(Pad.ref_t(), State.t()) :: State.t()
  def flush_for_pad(pad, bin_state) do
    buf = bin_state.linking_buffer

    case Map.pop(buf, pad, []) do
      {[], ^buf} ->
        bin_state

      {msgs, new_buf} ->
        msgs |> Enum.reverse() |> Enum.each(&do_flush(&1, pad, bin_state))
        %{bin_state | linking_buffer: new_buf}
    end
  end

  @spec flush_all_public_pads(State.t()) :: State.t()
  def flush_all_public_pads(bin_state) do
    buf = bin_state.linking_buffer

    public_pads =
      buf
      |> Enum.map(fn {pad_ref, _msgs} -> pad_ref end)
      |> Enum.filter(&(&1 |> Pad.name_by_ref() |> Pad.is_public_name()))

    public_pads
    |> Enum.reduce(bin_state, &flush_for_pad/2)
  end

  defp do_flush(msg, sender_pad, bin_state) do
    case PadModel.get_data(bin_state, sender_pad) do
      {:ok, %{pid: dest_pid, other_ref: other_ref}} ->
        send(dest_pid, Message.set_for_pad(msg, other_ref))

      _error ->
        Membrane.Logger.warn("flushed pad does not exist: #{inspect(sender_pad)}")
        :ok
    end
  end
end
