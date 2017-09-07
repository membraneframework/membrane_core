defmodule Membrane.Element.Manager.Common do

  use Membrane.Element.Manager.Log
  alias Membrane.Element.Manager.State
  use Membrane.Helper
  alias Membrane.PullBuffer

  defmacro __using__(_) do
    quote do
      use Membrane.Mixins.CallbackHandler
      alias Membrane.Element.Manager.{Action, Common, State}
      use Membrane.Helper

      def handle_action({:event, {pad_name, event}}, _cb, _params, state), do:
        Action.send_event(pad_name, event, state)

      def handle_action({:message, message}, _cb, _params, state), do:
        Action.send_message(message, state)

      def handle_actions(actions, callback, handler_params, state), do:
        super(actions |> Membrane.Element.Manager.Common.join_buffers, callback,
          handler_params, state)

      def handle_init(module, name, options) do
        use Membrane.Element.Manager.Log
        state = State.new(module, name)
        with {:ok, internal_state} <- module.handle_init(options)
        do {:ok, %State{state | internal_state: internal_state}}
        else
          {:error, reason} -> warn_error """
              Module #{inspect module} handle_init callback returned an error
              """, {:elementhandle_init, module, reason}, state
          other -> warn_error """
              Module #{inspect module} handle_init callback returned invalid result:
              #{inspect other} instead of {:ok, state} or {:error, reason}
            """, {:invalid_callback_result, :handle_init, other}, state
        end
      end

      def handle_message(message, state) do
        use Membrane.Element.Manager.Log
        exec_and_handle_callback(:handle_other, [message], state)
          |> or_warn_error("Error while handling message", state)
      end

      def handle_message_bus(message_bus, state), do:
        {:ok, %{state | message_bus: message_bus}}

      def handle_demand_in(demand_in, pad_name, state) do #TODO: move out of using
        {:ok, state} = state |>
          State.set_pad_data(:source, pad_name, [:options, :other_demand_in], demand_in)
      end

      def handle_playback_state(:prepared, :playing, state) do
        with \
          {:ok, state} <- state |> Common.fill_sink_pull_buffers,
          {:ok, state} <- exec_and_handle_callback(:handle_play, [], state),
          do: {:ok, state}
      end

      def handle_playback_state(:prepared, :stopped, state), do:
        exec_and_handle_callback :handle_stop, [], state

      def handle_playback_state(ps, :prepared, state) when ps in [:stopped, :playing], do:
        exec_and_handle_callback :handle_prepare, [ps], state

      def handle_new_pad(direction, {name, params}, state), do:
        exec_and_handle_callback name, direction, params, state

      def handle_linking_finished(state) do
        with {:ok, state} <- state.pads.new
          |> Helper.Enum.reduce_with(state, fn {name, direction}, st ->
            handle_pad_added name, direction, st end)
        do {:ok, state |> State.clear_new_pads}
        end
      end

      def handle_unlink(pad_name, state) do
        with \
          {:ok, state} <- exec_and_handle_callback(:handle_pad_removed, [pad_name], state),
          {:ok, state} <- state |> State.remove_pad_data(:any, pad_name),
        do: {:ok, state}
      end

      def unlink(%State{playback_state: :stopped} = state) do
        state
          |> State.get_pads_data
          |> Helper.Enum.each_with(fn {_name, %{pid: pid, other_name: other_name}}
            -> GenServer.call pid, {:membrane_handle_unlink, other_name} end)
      end
      def unlink(state) do
        use Membrane.Element.Manager.Log
        warn_error """
        Tried to unlink Element.Manager that is not stopped
        """, {:unlink, :cannot_unlink_non_stopped_element}, state
      end

      def handle_shutdown(%State{module: module, internal_state: internal_state} = state) do
        module.handle_shutdown(internal_state)
      end

    end
  end

  def available_actions, do: [
      "{:event, {pad_name, event}}",
      "{:message, message}",
    ]

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
    %{accepted_caps: accepted_caps, caps: old_caps} =
      state |> State.get_pad_data!(:sink, pad_name)
    params = %{caps: old_caps}
    with \
      :ok <- (if accepted_caps == :any || caps in accepted_caps do :ok else :invalid_caps end),
      {:ok, state} <- module.manager_module.exec_and_handle_callback(
        :handle_caps, %{caps: caps}, [pad_name, caps, params], state)
    do
      state |> State.set_pad_data(:sink, pad_name, :caps, caps)
    else
      :invalid_caps ->
        warn_error """
        Received caps: #{inspect caps} that are not specified in known_sink_pads
        for pad #{inspect pad_name}. Acceptable caps are:
        #{accepted_caps |> Enum.map(&inspect/1) |> Enum.join(", ")}
        """, :invalid_caps, state
      {:error, reason} -> warn_error "Error while handling caps", reason, state
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
    %{direction: dir, caps: caps} = state |> State.get_pad_data!(:any, pad_name)
    params = %{caps: caps}
    module.manager_module.exec_and_handle_callback(
      :handle_event, %{direction: dir, event: event}, [pad_name, event, params], state)
        |> or_warn_error("Error while handling event", state)
  end

  def handle_link(pad_name, direction, pid, other_name, props, state) do
    state |> State.update_pad_data(direction, pad_name, fn data -> data
        |> Map.merge(case {direction, data.mode} do
            {:sink, :pull} ->
              :ok = pid |> GenServer.call({:membrane_demand_in, [data.options.demand_in, other_name]})
              pb = PullBuffer.new({pid, other_name}, pad_name, data.options.demand_in, props[:pull_buffer] || %{})
              %{buffer: pb, self_demand: 0}
            {:source, :pull} -> %{demand: 0}
            {_, :push} -> %{}
          end)
        |> Map.merge(%{pid: pid, other_name: other_name})
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
    with {{:ok, actions}, state} <- inputs
      |> Membrane.Helper.Enum.map_reduce_with(state,
        fn i, st -> f.(i, st) ~> (
            {{:ok, actions}, _state} = ok when is_list actions -> ok
            {{:error, reason}, state} -> {{:error, {:internal, reason}}, state}
            other -> {:error, {:other, other}}
        ) end)
    do {{:ok, actions |> List.flatten}, state}
    else
      {{:error, {:internal, reason}}, st} -> {{:error, reason}, st}
      {{:error, {:other, other}}, _st} -> other
    end
  end


  def fill_sink_pull_buffers(state) do
    state
      |> State.get_pads_data(:sink)
      |> Map.keys
      |> Helper.Enum.reduce_with(state, fn pad_name, st ->
        State.update_pad_data st, :sink, pad_name, :buffer, &PullBuffer.fill/1
      end)
      |> or_warn_error("Unable to fill sink pull buffers", state)
  end

  def handle_new_pad(name, direction, args, %State{module: module, internal_state: internal_state} = state) do
    with \
      {{:ok, {_availability, _mode, _caps} = params}, internal_state} <-
        apply(module, :handle_new_pad, args ++ [internal_state])
    do
      state = state
        |> State.add_pad({name, params}, direction)
        |> Map.put(:internal_state, internal_state)
      {:ok, state}
    else
      {:error, reason} ->
        warn_error "handle_new_pad callback returned an error", reason, state
      res -> warn_error """
        handle_new_pad return values are expected to be
        {:ok, {{availability, mode, caps}, state}} or {:error, reason}
        but got #{inspect res} instead
        """, :invalid_handle_new_pad_return, state
    end
  end

  def handle_pad_added(args, %State{module: module} = state), do:
    module.manager_module.exec_and_handle_callback(:handle_pad_added, args, state)

end
