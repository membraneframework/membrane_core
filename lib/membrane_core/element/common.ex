defmodule Membrane.Element.Common do

  use Membrane.Mixins.Log
  alias Membrane.Element.State
  use Membrane.Helper
  alias Membrane.PullBuffer

  defmacro __using__(_) do
    quote do
      use Membrane.Mixins.CallbackHandler

      def handle_action({:event, {pad_name, event}}, _cb, state), do:
        Membrane.Element.Action.send_event(pad_name, event, state)

      def handle_action({:message, message}, _cb, state), do:
        Membrane.Element.Action.send_message(message, state)

      def handle_actions(actions, callback, handler_params, state), do:
        super(actions |> Membrane.Element.Common.join_buffers, callback,
          handler_params, state)

      def handle_message(message, state) do
        exec_and_handle_callback(:handle_other, [message], state)
          |> or_warn_error("Error while handling message")
      end

      def handle_playback_state(:prepared, :playing, state) do
        with {:ok, state} <- state |> Membrane.Element.Common.fill_sink_pull_buffers
        do exec_and_handle_callback :handle_play, [], state
        end
      end

      def handle_playback_state(:prepared, :stopped, state), do:
        exec_and_handle_callback :handle_stop, [], state

      def handle_playback_state(ps, :prepared, state) when ps in [:stopped, :playing], do:
        exec_and_handle_callback :handle_prepare, [ps], state

    end
  end

  def handle_caps(:pull, pad_name, caps, state) do
    cond do
      state |> State.get_pad_data!(:sink, pad_name, :buffer) |> PullBuffer.empty?
        -> do_handle_caps pad_name, caps, state
      true -> state |> State.update_pad_data(
        :sink, pad_name, :buffer, & &1 |> PullBuffer.store(:caps, caps))
    end
  end

  def handle_caps(:push, pad_name, caps, state), do:
    do_handle_caps(pad_name, caps, state)

  def do_handle_caps(pad_name, caps, %State{module: module} = state) do
    accepted_caps = state |> State.get_pad_data!(:sink, pad_name, :accepted_caps)
    params = %{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}
    with \
      :ok <- (if accepted_caps == :any || caps in accepted_caps do :ok else :invalid_caps end),
      {:ok, state} <- module.base_module.exec_and_handle_callback(:handle_caps, [pad_name, caps, params], state)
    do
      state |> State.set_pad_data(:sink, pad_name, :caps, caps)
    else
      :invalid_caps ->
        warn_error """
        Received caps: #{inspect caps} that are not specified in known_sink_pads
        for pad #{inspect pad_name}. Acceptable caps are:
        #{accepted_caps |> Enum.map(&inspect/1) |> Enum.join(", ")}
        """, :invalid_caps
      {:error, reason} -> warn_error "Error while handling caps", reason
    end
  end

  def handle_event(:pull, :sink, pad_name, event, state) do
    cond do
      state |> State.get_pad_data!(:sink, pad_name, :buffer) |> PullBuffer.empty?
        -> do_handle_event pad_name, event, state
      true -> state |> State.update_pad_data(
        :sink, pad_name, :buffer, & &1 |> PullBuffer.store(:event, event))
    end
  end

  def handle_event(_mode, _dir, pad_name, event, state), do:
    do_handle_event(pad_name, event, state)

  def do_handle_event(pad_name, event, %State{module: module} = state) do
    params = %{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}
    module.base_module.exec_and_handle_callback(:handle_event, [pad_name, event, params], state)
      |> or_warn_error("Error while handling event")
  end

  def handle_link(pad_name, direction, pid, props, state) do
    state |> State.update_pad_data(direction, pad_name, fn data -> data
        |> Map.merge(case direction do
            :sink -> %{buffer: PullBuffer.new(pid, pad_name, props), self_demand: 0}
            :source -> %{demand: 0}
          end)
        |> Map.merge(%{pid: pid})
        ~> (data -> {:ok, data})
      end)
  end

  def handle_pullbuffer_output(pad_name, {:event, e}, state), do:
    do_handle_event(pad_name, e, state)
  def handle_pullbuffer_output(pad_name, {:caps, c}, state), do:
    do_handle_caps(pad_name, c, state)

  def join_buffers(actions) do
    actions
      |> Helper.Enum.chunk_by(
        fn
          {:buffer, {pad, _}}, {:buffer, {pad2, _}} when pad == pad2 -> true
          _, _ -> false
        end,
        fn
          [{:buffer, {pad, _}}|_] = buffers ->
            {:buffer, {pad, buffers |> Enum.map(fn {_, {_, b}} -> [b] end) |> List.flatten}}
          [other] -> other
        end
      )
  end

  def reduce_something1_results(inputs, state, f) do
    with {:ok, {actions, state}} <- inputs
      |> Membrane.Helper.Enum.map_reduce_with(state,
        fn i, st -> f.(i, st) ~> (
            {:ok, {actions, _state}} = ok when is_list actions -> ok
            {:error, reason} -> {:error, {:internal, reason}}
            other -> {:error, {:other, other}}
        ) end)
    do {:ok, {actions |> List.flatten, state}}
    else
      {:error, {{:internal, reason}, st}} -> {:error, {reason, st}}
      {:error, {{:other, other}, _st}} -> other
    end
  end


  def fill_sink_pull_buffers(state) do
    state
      |> State.get_pads_data(:sink)
      |> Map.keys
      |> Helper.Enum.reduce_with(state, fn pad_name, st ->
        State.update_pad_data st, :sink, pad_name, :buffer, &PullBuffer.fill/1
      end)
      |> or_warn_error("Unable to fill sink pull buffers")
  end

end
