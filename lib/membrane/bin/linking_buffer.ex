defmodule Membrane.Bin.LinkingBuffer do
  alias Membrane.Core.Message
  alias Membrane.Core.Element.PadModel
  alias Membrane.Core.Pad
  alias Membrane.Bin
  require Message

  @type t :: Map.t()

  @doc """
  Creates a new linking buffer.
  """
  @spec new :: t()
  def new, do: Map.new()

  @doc """
  This function sends a message to pad, IF AND ONLY IF
  this pad is already linked. If it's not it is stored
  and will be sent after calling `eval_for_pad()`.
  Params:
  * buf - buffer structure
  * msg - message to be sent
  * outgoing_pad - pad from which the message is supposed
                   to be sent
  * bin_state - state of the bin
  """
  @spec store_or_send(t(), Message.t(), Pad.ref_t(), Bin.State.t()) :: t()
  def store_or_send(buf, msg, outgoing_pad, bin_state) do
    case PadModel.get_data(bin_state, outgoing_pad) do
      {:ok, %{pid: dest_pid, other_ref: other_ref}} ->
        send(dest_pid, Message.set_for_pad(msg, other_ref))
        buf

      {:error, {:unknown_pad, _}} ->
        Map.put(buf, outgoing_pad, msg)
    end
  end

  @doc """
  Sends messages stored for a given outpud pad.
  A link must already be available.
  """
  @spec eval_for_pad(t(), Pad.ref_t(), Bin.State.t()) :: t()
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
