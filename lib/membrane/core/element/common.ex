defmodule Membrane.Core.Element.Common do
  @moduledoc """
  Implementation of some functionalities common for all `Membrane.Core.Element`s.

  Key features:
  * handling actions with events, messages, split requests and playback changes
  * handling incoming events, caps and messages, element initializations, playback changes and executing element's callbacks
  * linking and unlinking pads
  """

  alias Membrane.{Buffer, Caps, Core, Element, Event}
  alias Membrane.Core.CallbackHandler
  alias Core.PullBuffer
  alias Element.Context
  alias Core.Element.{ActionHandler, PadModel, State}
  use Core.Element.Log
  use Membrane.Helper

  def unlink(%State{playback: %{state: :stopped}} = state) do
    PadModel.get_data(state)
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

  def handle_caps(:pull, pad_name, caps, state) do
    cond do
      PadModel.get_data!(:sink, pad_name, :buffer, state) |> PullBuffer.empty?() ->
        do_handle_caps(pad_name, caps, state)

      true ->
        PadModel.update_data(
          :sink,
          pad_name,
          :buffer,
          &(&1 |> PullBuffer.store(:caps, caps)),
          state
        )
    end
  end

  def handle_caps(:push, pad_name, caps, state), do: do_handle_caps(pad_name, caps, state)

  def do_handle_caps(pad_name, caps, state) do
    %{accepted_caps: accepted_caps, caps: old_caps} = PadModel.get_data!(:sink, pad_name, state)

    context = %Context.Caps{caps: old_caps}

    with :ok <- if(Caps.Matcher.match?(accepted_caps, caps), do: :ok, else: :invalid_caps),
         {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_caps,
             ActionHandler,
             [pad_name, caps, context],
             state
           ) do
      PadModel.set_data(:sink, pad_name, :caps, caps, state)
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
    pad_data = PadModel.get_data!(:any, pad_name, state)

    if event.mode == :sync && pad_data.mode == :pull && pad_data.direction == :sink &&
         pad_data.buffer |> PullBuffer.empty?() |> Kernel.not() do
      PadModel.update_data(
        :sink,
        pad_name,
        :buffer,
        &(&1 |> PullBuffer.store(:event, event)),
        state
      )
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
    with %{direction: :sink, sos: false} <- PadModel.get_data!(:any, pad_name, state) do
      {:ok, state} = PadModel.set_data(:sink, pad_name, :sos, true, state)
      {{:ok, :handle}, state}
    else
      %{direction: :source} -> {:error, {:received_sos_through_source, pad_name}}
      %{sos: true} -> {:error, {:sos_already_received, pad_name}}
    end
  end

  defp parse_event(pad_name, %Event{type: :eos}, state) do
    with %{direction: :sink, sos: true, eos: false} <- PadModel.get_data!(:any, pad_name, state) do
      {:ok, state} = PadModel.set_data(:sink, pad_name, :eos, true, state)
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
    %{direction: dir, caps: caps} = PadModel.get_data!(:any, pad_name, state)
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
      PadModel.update_data(:sink, pad_name, :self_demand, &{:ok, &1 - buf_cnt}, state)

    context = %Context.Write{caps: PadModel.get_data!(:sink, pad_name, :caps, state)}
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
      caps: PadModel.get_data!(:sink, pad_name, :caps, state),
      source: source,
      source_caps: PadModel.get_data!(:sink, pad_name, :caps, state)
    }

    CallbackHandler.exec_and_handle_callback(
      :handle_process,
      ActionHandler,
      [pad_name, buffers, context],
      state
    )
  end

  def fill_sink_pull_buffers(state) do
    PadModel.get_data(:sink, state)
    |> Enum.filter(fn {_, %{mode: mode}} -> mode == :pull end)
    |> Helper.Enum.reduce_with(state, fn {pad_name, _pad_data}, st ->
      PadModel.update_data(:sink, pad_name, :buffer, &PullBuffer.fill/1, st)
    end)
    |> or_warn_error("Unable to fill sink pull buffers")
  end

  def handle_redemand(src_name, state) do
    handle_demand(src_name, 0, state)
  end

  def handle_demand(pad_name, size, state) do
    {{:ok, total_size}, state} =
      PadModel.get_update_data(
        :source,
        pad_name,
        :demand,
        &{{:ok, &1 + size}, &1 + size},
        state
      )

    if exec_handle_demand?(pad_name, state) do
      %{caps: caps, options: %{other_demand_in: demand_in}} =
        PadModel.get_data!(:source, pad_name, state)

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
    case PadModel.get_data!(:source, pad_name, state) do
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
          PadModel.update_data(:sink, pad_name, :self_demand, &{:ok, &1 + buf_cnt}, state)

        :set ->
          PadModel.set_data(:sink, pad_name, :self_demand, buf_cnt, state)
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
      PadModel.get_update_data(
        :sink,
        pad_name,
        :buffer,
        fn pb ->
          was_empty = pb |> PullBuffer.empty?()

          with {:ok, pb} <- pb |> PullBuffer.store(buffers) do
            {{:ok, was_empty}, pb}
          end
        end,
        state
      )

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
      PadModel.update_data(
        :sink,
        pad_name,
        :buffer,
        &(&1 |> PullBuffer.store(buffer)),
        state
      )

    check_and_handle_write(pad_name, state)
    |> or_warn_error(["
        New buffer arrived:", Buffer.print(buffer), "
        and Membrane tried to execute handle_demand and then handle_write
        for each unsupplied demand, but an error happened.
        "])
  end

  def handle_process_push(pad_name, buffers, state) do
    context = %Context.Process{
      caps: PadModel.get_data!(:sink, pad_name, :caps, state)
    }

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
           PadModel.get_update_data(
             :sink,
             pad_name,
             :buffer,
             &(&1 |> PullBuffer.take(buf_cnt)),
             state
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
    context = %Context.Write{caps: PadModel.get_data!(:sink, pad_name, :caps, state)}

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
           PadModel.get_update_data(
             :sink,
             pad_name,
             fn %{
                  self_demand: demand,
                  buffer: pb
                } = data ->
               with {{:ok, out}, npb} <- PullBuffer.take(pb, demand) do
                 {{:ok, out}, %{data | buffer: npb}}
               end
             end,
             state
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
    if PadModel.get_data!(:sink, pad_name, :buffer, state)
       |> PullBuffer.empty?()
       |> Kernel.!() && PadModel.get_data!(:source, src_name, :demand, state) > 0 do
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
    demand = PadModel.get_data!(:sink, pad_name, :self_demand, state)

    if demand > 0 do
      handle_process_pull(pad_name, nil, demand, state)
    else
      {:ok, state}
    end
  end

  defp check_and_handle_demands(state) do
    PadModel.get_data(:source, state)
    |> Helper.Enum.reduce_with(state, fn {name, _data}, st ->
      handle_demand(name, 0, st)
    end)
    |> or_warn_error("""
    Membrane tried to execute handle_demand and then handle_process
    for each unsupplied demand, but an error happened.
    """)
  end

  defp update_sink_self_demand(state, pad_name, :self, f),
    do: PadModel.update_data(:sink, pad_name, :self_demand, f, state)

  defp update_sink_self_demand(state, _pad_name, _src, _f), do: {:ok, state}

  defp check_and_handle_write(pad_name, state) do
    if PadModel.get_data!(:sink, pad_name, :self_demand, state) > 0 do
      handle_write(:pull, pad_name, state)
    else
      {:ok, state}
    end
  end
end
