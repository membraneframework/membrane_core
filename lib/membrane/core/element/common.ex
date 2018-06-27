defmodule Membrane.Core.Element.Common do
  @moduledoc """
  Implementation of some functionalities common for all `Membrane.Core.Element`s.

  Key features:
  * handling actions with events, messages, split requests and playback changes
  * handling incoming events, caps and messages, element initializations, playback changes and executing element's callbacks
  * linking and unlinking pads
  """

  alias Membrane.{Buffer, Caps, Core, Element, Event}
  alias Membrane.Mixins.CallbackHandler
  alias Core.PullBuffer
  alias Element.Context
  alias Core.Element.{ActionHandler, State}
  use Core.Element.Log
  use Membrane.Helper

  def handle_init(module, name, options) do
    with {:ok, state} <- State.new(module, name) do
      do_handle_init(module, options, state)
    end
  end

  defp do_handle_init(module, options, state) do
    with {:ok, internal_state} <- module.handle_init(options) do
      {:ok, %State{state | internal_state: internal_state}}
    else
      {:error, reason} ->
        warn_error(
          """
          Module #{inspect(module)} handle_init callback returned an error
          """,
          {:handle_init, module, reason},
          state
        )

      other ->
        warn_error(
          """
          Module #{inspect(module)} handle_init callback returned invalid result:
          #{inspect(other)} instead of {:ok, state} or {:error, reason}
          """,
          {:invalid_callback_result, :handle_init, other},
          state
        )
    end
  end

  def handle_message(message, state) do
    CallbackHandler.exec_and_handle_callback(:handle_other, ActionHandler, [message], state)
    |> or_warn_error("Error while handling message")
  end

  def handle_message_bus(message_bus, state), do: {:ok, %{state | message_bus: message_bus}}

  def handle_controlling_pid(pid, state), do: {:ok, %{state | controlling_pid: pid}}

  def handle_demand_in(demand_in, pad_name, state) do
    state
    |> State.set_pad_data(:source, pad_name, [:options, :other_demand_in], demand_in)
  end

  def handle_playback_state(:prepared, :playing, state),
    do: CallbackHandler.exec_and_handle_callback(:handle_play, ActionHandler, [], state)

  def handle_playback_state(:prepared, :stopped, state),
    do: CallbackHandler.exec_and_handle_callback(:handle_stop, ActionHandler, [], state)

  def handle_playback_state(ps, :prepared, state) when ps in [:stopped, :playing],
    do: CallbackHandler.exec_and_handle_callback(:handle_prepare, ActionHandler, [ps], state)

  def get_pad_full_name(pad_name, state) do
    state |> State.resolve_pad_full_name(pad_name)
  end

  def handle_link(pad_name, pad_direction, pid, other_name, props, state) do
    state
    |> State.link_pad(pad_name, pad_direction, fn %{direction: dir, mode: mode} = data ->
      data
      |> Map.merge(
        case dir do
          :source -> %{}
          :sink -> %{sticky_messages: []}
        end
      )
      |> Map.merge(
        case {dir, mode} do
          {:sink, :pull} ->
            :ok =
              pid
              |> GenServer.call({:membrane_demand_in, [data.options.demand_in, other_name]})

            pb =
              PullBuffer.new(
                state.name,
                {pid, other_name},
                pad_name,
                data.options.demand_in,
                props[:pull_buffer] || %{}
              )

            {:ok, pb} = pb |> PullBuffer.fill()
            %{buffer: pb, self_demand: 0}

          {:source, :pull} ->
            %{demand: 0}

          {_, :push} ->
            %{}
        end
      )
      |> Map.merge(%{name: pad_name, pid: pid, other_name: other_name})
    end)
  end

  def handle_linking_finished(state) do
    with {:ok, state} <-
           state.pads.dynamic_currently_linking
           |> Helper.Enum.reduce_with(state, fn name, st ->
             {:ok, direction} = st |> State.get_pad_data(:any, name, :direction)
             handle_pad_added(name, direction, st)
           end) do
      static_unlinked =
        state.pads.info
        |> Map.values()
        |> Enum.filter(&(!&1.is_dynamic))
        |> Enum.map(& &1.name)

      if(static_unlinked |> Enum.empty?() |> Kernel.!()) do
        warn(
          """
          Some static pads remained unlinked: #{inspect(static_unlinked)}
          """,
          state
        )
      end

      {:ok, state |> State.clear_currently_linking()}
    end
  end

  def handle_unlink(pad_name, state) do
    with {:ok, state} <-
           state
           |> State.get_pad_data(:sink, pad_name)
           |> (case do
                 {:ok, %{eos: false}} ->
                   handle_event(
                     pad_name,
                     %{Event.eos() | payload: :auto_eos, mode: :async},
                     state
                   )

                 _ ->
                   {:ok, state}
               end),
         {:ok, caps} <- state |> State.get_pad_data(:any, pad_name, :caps),
         {:ok, direction} <- state |> State.get_pad_data(:any, pad_name, :direction),
         context <- %Context.PadRemoved{direction: direction, caps: caps},
         {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_pad_removed,
             ActionHandler,
             [pad_name, context],
             state
           ),
         {:ok, state} <- state |> State.remove_pad_data(:any, pad_name) do
      {:ok, state}
    end
  end

  def unlink(%State{playback: %{state: :stopped}} = state) do
    state
    |> State.get_pads_data()
    |> Helper.Enum.each_with(fn {_name, %{pid: pid, other_name: other_name}} ->
      GenServer.call(pid, {:membrane_handle_unlink, other_name})
    end)
  end

  def unlink(state) do
    warn_error(
      """
      Tried to unlink Element that is not stopped
      """,
      {:unlink, :cannot_unlink_non_stopped_element},
      state
    )
  end

  def handle_shutdown(%State{module: module, internal_state: internal_state}) do
    module.handle_shutdown(internal_state)
  end

  def handle_pad_added(name, direction, state) do
    context = %Context.PadAdded{
      direction: direction
    }

    CallbackHandler.exec_and_handle_callback(
      :handle_pad_added,
      ActionHandler,
      [name, context],
      state
    )
  end

  def handle_caps(:pull, pad_name, caps, state) do
    cond do
      state |> State.get_pad_data!(:sink, pad_name, :buffer) |> PullBuffer.empty?() ->
        do_handle_caps(pad_name, caps, state)

      true ->
        state
        |> State.update_pad_data(:sink, pad_name, :buffer, &(&1 |> PullBuffer.store(:caps, caps)))
    end
  end

  def handle_caps(:push, pad_name, caps, state), do: do_handle_caps(pad_name, caps, state)

  def do_handle_caps(pad_name, caps, state) do
    %{accepted_caps: accepted_caps, caps: old_caps} =
      state |> State.get_pad_data!(:sink, pad_name)

    context = %Context.Caps{caps: old_caps}

    with :ok <- if(Caps.Matcher.match?(accepted_caps, caps), do: :ok, else: :invalid_caps),
         {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_caps,
             ActionHandler,
             [pad_name, caps, context],
             state
           ) do
      state |> State.set_pad_data(:sink, pad_name, :caps, caps)
    else
      :invalid_caps ->
        warn_error(
          """
          Received caps: #{inspect(caps)} that are not specified in known_sink_pads
          for pad #{inspect(pad_name)}. Specs of accepted caps are:
          #{inspect(accepted_caps, pretty: true)}
          """,
          :invalid_caps,
          state
        )

      {:error, reason} ->
        warn_error("Error while handling caps", reason, state)
    end
  end

  def handle_event(pad_name, event, state) do
    pad_data = state |> State.get_pad_data!(:any, pad_name)

    if event.mode == :sync && pad_data.mode == :pull && pad_data.direction == :sink &&
         pad_data.buffer |> PullBuffer.empty?() |> Kernel.not() do
      state
      |> State.update_pad_data(:sink, pad_name, :buffer, &(&1 |> PullBuffer.store(:event, event)))
    else
      do_handle_event(pad_name, event, state)
    end
  end

  defp do_handle_event(pad_name, event, state) do
    with {{:ok, :handle}, state} <- parse_event(pad_name, event, state),
         {:ok, state} <- exec_event_handler(pad_name, event, state) do
      {:ok, state}
    else
      {{:ok, :ignore}, state} ->
        debug("ignoring event #{inspect(event)}", state)
        {:ok, state}

      {:error, reason} ->
        warn_error("Error while handling event", {:handle_event, reason}, state)
    end
  end

  defp parse_event(pad_name, %Event{type: :sos}, state) do
    with %{direction: :sink, sos: false} <- state |> State.get_pad_data!(:any, pad_name) do
      {:ok, state} = state |> State.set_pad_data(:sink, pad_name, :sos, true)
      {{:ok, :handle}, state}
    else
      %{direction: :source} -> {:error, {:received_sos_through_source, pad_name}}
      %{sos: true} -> {:error, {:sos_already_received, pad_name}}
    end
  end

  defp parse_event(pad_name, %Event{type: :eos}, state) do
    with %{direction: :sink, sos: true, eos: false} <-
           state |> State.get_pad_data!(:any, pad_name) do
      {:ok, state} = state |> State.set_pad_data(:sink, pad_name, :eos, true)
      {{:ok, :handle}, state}
    else
      %{direction: :source} -> {:error, {:received_eos_through_source, pad_name}}
      %{eos: true} -> {:error, {:eos_already_received, pad_name}}
      %{sos: false} -> {{:ok, :ignore}, state}
    end
  end

  # FIXME: solve it using pipeline messages, not events
  defp parse_event(_pad_name, %Event{type: :dump_state}, state) do
    IO.puts("""
    state dump for #{inspect(state.name)} at #{inspect(self())}
    state:
    #{inspect(state)}
    info:
    #{inspect(:erlang.process_info(self()))}
    """)

    {{:ok, :handle}, state}
  end

  defp parse_event(_pad_name, _event, state), do: {{:ok, :handle}, state}

  def exec_event_handler(pad_name, event, state) do
    %{direction: dir, caps: caps} = state |> State.get_pad_data!(:any, pad_name)
    context = %Context.Event{caps: caps}

    CallbackHandler.exec_and_handle_callback(
      :handle_event,
      ActionHandler,
      %{direction: dir},
      [pad_name, event, context],
      state
    )
  end

  defp handle_pullbuffer_output(pad_name, _source, {:event, e}, state),
    do: do_handle_event(pad_name, e, state)

  defp handle_pullbuffer_output(pad_name, _source, {:caps, c}, state),
    do: do_handle_caps(pad_name, c, state)

  defp handle_pullbuffer_output(
         pad_name,
         _source,
         {:buffers, buffers, buf_cnt},
         %State{type: :sink} = state
       ) do
    {:ok, state} =
      state
      |> State.update_pad_data(:sink, pad_name, :self_demand, &{:ok, &1 - buf_cnt})

    context = %Context.Write{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}
    debug("Executing handle_write with buffers #{inspect(buffers)}", state)

    CallbackHandler.exec_and_handle_callback(
      :handle_write,
      ActionHandler,
      [pad_name, buffers, context],
      state
    )
  end

  defp handle_pullbuffer_output(
         pad_name,
         source,
         {:buffers, buffers, buf_cnt},
         %State{type: :filter} = state
       ) do
    {:ok, state} = state |> update_sink_self_demand(pad_name, source, &{:ok, &1 - buf_cnt})

    context = %Context.Process{
      caps: state |> State.get_pad_data!(:sink, pad_name, :caps),
      source: source,
      source_caps: state |> State.get_pad_data!(:sink, pad_name, :caps)
    }

    CallbackHandler.exec_and_handle_callback(
      :handle_process,
      ActionHandler,
      [pad_name, buffers, context],
      state
    )
  end

  def fill_sink_pull_buffers(state) do
    state
    |> State.get_pads_data(:sink)
    |> Enum.filter(fn {_, %{mode: mode}} -> mode == :pull end)
    |> Helper.Enum.reduce_with(state, fn {pad_name, _pad_data}, st ->
      State.update_pad_data(st, :sink, pad_name, :buffer, &PullBuffer.fill/1)
    end)
    |> or_warn_error("Unable to fill sink pull buffers")
  end

  def handle_redemand(src_name, state) do
    handle_demand(src_name, 0, state)
  end

  def handle_demand(pad_name, size, state) do
    {{:ok, total_size}, state} =
      state
      |> State.get_update_pad_data(:source, pad_name, :demand, &{{:ok, &1 + size}, &1 + size})

    if exec_handle_demand?(pad_name, state) do
      %{caps: caps, options: %{other_demand_in: demand_in}} =
        state |> State.get_pad_data!(:source, pad_name)

      context = %Context.Demand{caps: caps}

      CallbackHandler.exec_and_handle_callback(
        :handle_demand,
        ActionHandler,
        %{source: pad_name, split_cont_f: &exec_handle_demand?(pad_name, &1)},
        [pad_name, total_size, demand_in, context],
        state
      )
      |> or_warn_error("""
      Demand arrived from pad #{inspect(pad_name)}, but error happened while
      handling it.
      """)
    else
      {:ok, state}
    end
  end

  defp exec_handle_demand?(pad_name, state) do
    case state |> State.get_pad_data!(:source, pad_name) do
      %{eos: true} ->
        debug(
          """
          Demand handler: not executing handle_demand, as EoS has already been sent
          """,
          state
        )

        false

      %{demand: demand} when demand <= 0 ->
        debug(
          """
          Demand handler: not executing handle_demand, as demand is not greater than 0,
          demand: #{inspect(demand)}
          """,
          state
        )

        false

      _ ->
        true
    end
  end

  def handle_self_demand(pad_name, source, :normal, buf_cnt, %State{type: :filter} = state) do
    {:ok, state} = state |> update_sink_self_demand(pad_name, source, &{:ok, &1 + buf_cnt})

    handle_process_pull(pad_name, source, buf_cnt, state)
    |> or_warn_error("""
    Demand of size #{inspect(buf_cnt)} on sink pad #{inspect(pad_name)}
    was raised, and handle_process was called, but an error happened.
    """)
  end

  def handle_self_demand(pad_name, :self, type, buf_cnt, %State{type: :sink} = state) do
    {:ok, state} =
      case type do
        :normal ->
          state
          |> State.update_pad_data(:sink, pad_name, :self_demand, &{:ok, &1 + buf_cnt})

        :set ->
          state
          |> State.set_pad_data(:sink, pad_name, :self_demand, buf_cnt)
      end

    handle_write(:pull, pad_name, state)
    |> or_warn_error("""
    Demand of size #{inspect(buf_cnt)} on pad #{inspect(pad_name)}
    was raised, and handle_write was called, but an error happened.
    """)
  end

  def handle_buffer(:push, pad_name, buffers, %State{type: :filter} = state) do
    handle_process_push(pad_name, buffers, state)
  end

  def handle_buffer(:pull, pad_name, buffers, %State{type: :filter} = state) do
    {{:ok, was_empty?}, state} =
      state
      |> State.get_update_pad_data(:sink, pad_name, :buffer, fn pb ->
        was_empty = pb |> PullBuffer.empty?()

        with {:ok, pb} <- pb |> PullBuffer.store(buffers) do
          {{:ok, was_empty}, pb}
        end
      end)

    if was_empty? do
      with {:ok, state} <- check_and_handle_process(pad_name, state),
           {:ok, state} <- check_and_handle_demands(state),
           do: {:ok, state}
    else
      {:ok, state}
    end
  end

  def handle_buffer(:push, pad_name, buffer, %State{type: :sink} = state),
    do: handle_write(:push, pad_name, buffer, state)

  def handle_buffer(:pull, pad_name, buffer, %State{type: :sink} = state) do
    {:ok, state} =
      state
      |> State.update_pad_data(:sink, pad_name, :buffer, &(&1 |> PullBuffer.store(buffer)))

    check_and_handle_write(pad_name, state)
    |> or_warn_error(["
        New buffer arrived:", Buffer.print(buffer), "
        and Membrane tried to execute handle_demand and then handle_write
        for each unsupplied demand, but an error happened.
        "])
  end

  def handle_process_push(pad_name, buffers, state) do
    context = %Context.Process{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}

    CallbackHandler.exec_and_handle_callback(
      :handle_process,
      ActionHandler,
      [pad_name, buffers, context],
      state
    )
    |> or_warn_error("Error while handling process")
  end

  def handle_process_pull(pad_name, source, buf_cnt, state) do
    with {{:ok, out}, state} <-
           state
           |> State.get_update_pad_data(
             :sink,
             pad_name,
             :buffer,
             &(&1 |> PullBuffer.take(buf_cnt))
           ),
         {:out, {_, data}} <-
           (if out == {:empty, []} do
              {:empty_pb, state}
            else
              {:out, out}
            end),
         {:ok, state} <-
           data
           |> Helper.Enum.reduce_with(state, fn v, st ->
             handle_pullbuffer_output(pad_name, source, v, st)
           end) do
      :ok = send_dumb_demand_if_demand_positive_and_pullbuffer_nonempty(pad_name, source, state)
      {:ok, state}
    else
      {:empty_pb, state} -> {:ok, state}
      {:error, reason} -> warn_error("Error while handling process", reason, state)
    end
  end

  def handle_write(:push, pad_name, buffers, state) do
    context = %Context.Write{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}

    CallbackHandler.exec_and_handle_callback(
      :handle_write,
      ActionHandler,
      [pad_name, buffers, context],
      state
    )
    |> or_warn_error("Error while handling write")
  end

  def handle_write(:pull, pad_name, state) do
    with {{:ok, out}, state} <-
           state
           |> State.get_update_pad_data(:sink, pad_name, fn %{self_demand: demand, buffer: pb} =
                                                              data ->
             with {{:ok, out}, npb} <- PullBuffer.take(pb, demand) do
               {{:ok, out}, %{data | buffer: npb}}
             end
           end),
         {:out, {_, data}} <-
           (if out == {:empty, []} do
              {:empty_pb, state}
            else
              {:out, out}
            end),
         {:ok, state} <-
           data
           |> Helper.Enum.reduce_with(state, fn v, st ->
             handle_pullbuffer_output(pad_name, :self, v, st)
           end) do
      {:ok, state}
    else
      {:empty_pb, state} -> {:ok, state}
      {:error, reason} -> warn_error("Error while handling write", reason, state)
    end
  end

  defp send_dumb_demand_if_demand_positive_and_pullbuffer_nonempty(_pad_name, :self, _state),
    do: :ok

  defp send_dumb_demand_if_demand_positive_and_pullbuffer_nonempty(
         pad_name,
         {:source, src_name},
         state
       ) do
    if state
       |> State.get_pad_data!(:sink, pad_name, :buffer)
       |> PullBuffer.empty?()
       |> Kernel.!() && state |> State.get_pad_data!(:source, src_name, :demand) > 0 do
      debug(
        """
        handle_process did not produce expected amount of buffers, despite
        PullBuffer being not empty. Trying executing handle_demand again.
        """,
        state
      )

      send(self(), {:membrane_demand, [0, src_name]})
    end

    :ok
  end

  defp check_and_handle_process(pad_name, state) do
    demand = state |> State.get_pad_data!(:sink, pad_name, :self_demand)

    if demand > 0 do
      handle_process_pull(pad_name, nil, demand, state)
    else
      {:ok, state}
    end
  end

  defp check_and_handle_demands(state) do
    state
    |> State.get_pads_data(:source)
    |> Helper.Enum.reduce_with(state, fn {name, _data}, st ->
      handle_demand(name, 0, st)
    end)
    |> or_warn_error("""
    Membrane tried to execute handle_demand and then handle_process
    for each unsupplied demand, but an error happened.
    """)
  end

  defp update_sink_self_demand(state, pad_name, :self, f),
    do: state |> State.update_pad_data(:sink, pad_name, :self_demand, f)

  defp update_sink_self_demand(state, _pad_name, _src, _f), do: {:ok, state}

  defp check_and_handle_write(pad_name, state) do
    if State.get_pad_data!(state, :sink, pad_name, :self_demand) > 0 do
      handle_write(:pull, pad_name, state)
    else
      {:ok, state}
    end
  end
end
