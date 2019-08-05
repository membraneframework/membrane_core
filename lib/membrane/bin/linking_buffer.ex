defmodule Membrane.Bin.LinkingBuffer do
  alias Membrane.Core.Message
  alias Membrane.Core.Element.PadModel
  require Message

  def new, do: Map.new()

  # %{dest_pad => msg}
  # TODO what with empty buf?
  def store_or_send(buf, msg, outgoing_pad, bin_state) do
    case PadModel.get_data(bin_state, outgoing_pad) do
      {:ok, %{pid: dest_pid, other_ref: other_ref}} ->
        send(dest_pid, Message.set_for_pad(msg, other_ref))
        buf

      {:error, {:unknown_pad, _}} ->
        Map.put(buf, outgoing_pad, msg)
    end
  end

  def eval_for_pad(buf, pad, bin_state) do
    case Map.pop(buf, pad) do
      {nil, ^buf} ->
        buf

      {msg, new_buf} ->
        do_eval(msg, pad, bin_state)
        new_buf
    end
  end

  defp do_eval(msg, outgoing_pad, bin_state) do
    {:ok, %{pid: dest_pid, other_ref: other_ref}} = PadModel.get_data(bin_state, outgoing_pad)
    send(dest_pid, Message.set_for_pad(msg, other_ref))
  end
end
