defmodule Membrane.Element.Manager.Common do

  use Membrane.Element.Manager.Log
  alias Membrane.Element.Manager.State
  use Membrane.Helper
  alias Membrane.PullBuffer
  alias Membrane.Event

  defmacro __using__(_) do
    quote location: :keep do
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

      def callback_handler_warn_error(message, reason, state) do
        use Membrane.Element.Manager.Log
        warn_error message, reason, state
      end
      def playback_warn_error(message, reason, state) do
        use Membrane.Element.Manager.Log
        warn_error message, reason, state
      end

      def handle_init(module, name, options) do
        with {:ok, state} <- State.new(module, name)
        do do_handle_init module, name, options, state
        end
      end

      defp do_handle_init(module, name, options, state) do
        use Membrane.Element.Manager.Log
        with {:ok, internal_state} <- module.handle_init(options)
        do {:ok, %State{state | internal_state: internal_state}}
        else
          {:error, reason} -> warn_error """
              Module #{inspect module} handle_init callback returned an error
              """, {:handle_init, module, reason}, state
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
          {:ok, state} <- exec_and_handle_callback(:handle_play, [], state),
          do: {:ok, state}
      end

      def handle_playback_state(:prepared, :stopped, state), do:
        exec_and_handle_callback :handle_stop, [], state

      def handle_playback_state(ps, :prepared, state) when ps in [:stopped, :playing], do:
        exec_and_handle_callback :handle_prepare, [ps], state

      def get_pad_full_name(pad_name, state) do
        state |> State.resolve_pad_full_name(pad_name)
      end

      def handle_link(pad_name, pid, other_name, props, state) do
        state |> State.link_pad(pad_name, fn %{direction: dir, mode: mode} = data -> data
            |> Map.merge(case {dir, mode} do
                {:sink, :pull} ->
                  :ok = pid |> GenServer.call({:membrane_demand_in, [data.options.demand_in, other_name]})
                  pb = PullBuffer.new(state.name, {pid, other_name}, pad_name, data.options.demand_in, props[:pull_buffer] || %{})
                  {:ok, pb} = pb |> PullBuffer.fill
                  %{buffer: pb, self_demand: 0}
                {:source, :pull} -> %{demand: 0}
                {_, :push} -> %{}
              end)
            |> Map.merge(%{name: pad_name, pid: pid, other_name: other_name})
          end)
      end

      def handle_linking_finished(state) do
        with {:ok, state} <- state.pads.dynamic_currently_linking
          |> Helper.Enum.reduce_with(state, fn name, st ->
            {:ok, direction} = st |> State.get_pad_data(:any, name, :direction)
            handle_pad_added name, direction, st end)
        do
          static_unlinked = state.pads.info
            |> Map.values
            |> Enum.filter(& !&1.is_dynamic)
            |> Enum.map(& &1.name)
          if(static_unlinked |> Enum.empty? |> Kernel.!) do
            warn """
            Some static pads remained unlinked: #{inspect static_unlinked}
            """, state
          end
          {:ok, state |> State.clear_currently_linking}
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

  def do_handle_event(pad_name, event, state) do
    with \
      {:ok, state} <- parse_event(pad_name, event, state),
      {:ok, state} <- exec_event_handler(pad_name, event, state)
    do
      {:ok, state}
    else
      {:error, reason} ->
        warn_error "Error while handling event", {:handle_event, reason}, state
    end
  end

  def parse_event(pad_name, %Event{type: :eos}, state) do
    with %{direction: :sink, eos: false} <- state |> State.get_pad_data!(:any, pad_name)
    do
      state |> State.set_pad_data(:sink, pad_name, :eos, true)
    else
      %{direction: :source} -> {:error, {:received_eos_through_source, pad_name}}
      %{eos: true} -> {:error, {:eos_already_received, pad_name}}
    end
  end
  def parse_event(_pad_name, _event, state), do: {:ok, state}

  def exec_event_handler(pad_name, event, %State{module: module} = state) do
    %{direction: dir, caps: caps} = state |> State.get_pad_data!(:any, pad_name)
    params = %{caps: caps}
    module.manager_module.exec_and_handle_callback(
      :handle_event, %{direction: dir, event: event}, [pad_name, event, params], state)
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
    use Membrane.Mixins.Log
    with {{:ok, actions}, state} <- inputs
      |> Membrane.Helper.Enum.map_reduce_with(state,
        fn i, st -> f.(i, st) ~> (
            {:ok, state} -> {{:ok, []}, state}
            {{:ok, actions}, _state} = ok when is_list actions -> ok
            {{:error, reason}, state} -> {{:error, {:internal, reason}}, state}
            other -> {:error, {:other, other}}
        ) end)
    do {{:ok, actions |> List.flatten}, state}
    else
      {{:error, {:internal, reason}}, st} -> {{:error, reason}, st}
      {{:error, {:other, other}}, _st} ->
        warn "Reducing results: invalid callback return: #{inspect other}"
        other
    end
  end


  def fill_sink_pull_buffers(state) do
    state
      |> State.get_pads_data(:sink)
      |> Enum.filter(fn {_, %{mode: mode}} -> mode == :pull end)
      |> Helper.Enum.reduce_with(state, fn {pad_name, _pad_data}, st ->
        State.update_pad_data st, :sink, pad_name, :buffer, &PullBuffer.fill/1
      end)
      |> or_warn_error("Unable to fill sink pull buffers", state)
  end

  def handle_pad_added(args, %State{module: module} = state), do:
    module.manager_module.exec_and_handle_callback(:handle_pad_added, args, state)

end
