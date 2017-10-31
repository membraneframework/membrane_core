defmodule Membrane.Element.Manager.Filter do
  @moduledoc """
  Base module to be used by all elements that are filters, in other words,
  elements that process the buffers going through them. Some examples might be:
  an MP3 decoder, a video resizer.

  ## Callbacks

  As for all base elements in the Membrane Framework, lifecycle of sinks is
  defined by set of callbacks. All of them have names with the `handle_` prefix.
  They are used to define reaction to certain events that happen during runtime,
  and indicate what actions frawork should undertake as a result, besides
  executing element-specific code.

  Sinks have a callback that will be core to their operations in all sane cases:
  `handle_process/3` which gets called when data is available and should be
  processed. Usually then filter returns `:buffer` action which causes to send
  buffers to the subsequent elements.

  ## Actions

  All callbacks have to return a value.

  If they were successful they return `{:ok, actions, new_state}` tuple,
  where `actions` is a list of actions to be undertaken by the framework after
  the callback has finished its execution.

  They are combination of actions that can be returned by sources and sinks,
  and each action may be one of the following:

  * `{:buffer, {pad_name, buffer}}` - it will cause sending given buffer
    from pad of given name to its peer. Pad must be a source pad.
  * `{:caps, {pad_name, caps}}` - it will cause sending new caps for pad of
    given name.
  * `{:demand, pad_name}` - it will cause sending request for more buffers to
    the pad of given name.
  * `{:event, {pad_name, event}}` - it will cause sending given event
    from pad of given name to its peer. Pad may be either source or sink pad.
  * `{:message, message}` - it will cause sending given message to the element's
    message bus (usually a pipeline) if any is defined,

  ## Demand

  Please note however, that if it has source pads in the pull mode, which are
  triggered by demand coming from sinks, the `handle_process/3` callback
  should not return more than one buffer per one `handle_demand/2` call.
  In such case, if upstream Element.Manager has sent more data than for one buffer,
  the remaining preprocessed data, or postprocessed buffers made out of it
  (whatever is more appropriate in case of the particular element) should
  remain cached in the element's state and released upon next `handle_demand/2`.

  The real-life scenario might be parsing a MP3 file read from the
  hard drive. File source for each demand will output one buffer which will
  contain e.g. 16kB of data. It will be sent to the parser which splits it
  into MP3 frames. Each 16kB chunk will contain many frames, but parser should
  output only one and keep rest in cache. When next demand request arrives,
  parser should release frame in cache and do not trigger reading more data
  from the file. Only when cache is empty it should ask file reader for more
  data. In such way we do not generate excessive throughput.

  ## Example

  The simplest possible filter Element.Manager working in the pull mode may look like
  the following. It gets buffers from upstream (we assume buffers' payload
  are strings), splits them into individual letters and send these individual
  letters as buffers:

      defmodule Membrane.Element.Manager.Sample.Filter do
        use Membrane.Element.Manager.Base.Filter

        def_known_source_pads %{
          :source => {:always, :pull, :any}
        }

        def_known_sink_pads %{
          :sink => {:always, :pull, :any}
        }

        # Private API

        @doc false
        def handle_init(_options) do
          # Initialize state with cache based on erlang's :queue
          {:ok, %{
            cache: :queue.new()
          }}
        end

        @doc false
        def handle_demand(_pad, %{cache: cache} = state) do
          case :queue.out(cache) do
            {:empty, _cache} ->
              # Request more data if the cache is empty
              # FIXME potential race condition - we forward demand and new
              # demand comes faster than we process and process returns twice
              {:ok, [
                {:demand, :sink}
              ], state}

            {{:value, item}, new_cache} ->
              # Send cached item if the cache is not empty
              {:ok, [
                {:buffer, {:source, item}}
              ], %{state | cache: new_cache}}
          end
        end

        @doc false
        def handle_process(_pad, %Membrane.Buffer{payload: payload}, %{cache: cache} = state) do
          # Process one buffer from upstream, split it into individual letters
          # that will be later sent upon each demand request.
          new_cache =
            payload
            |> String.split
            |> Enum.reduce(cache, fn(item, acc) ->
              :queue.in(acc, item)
            end)

          # Because it is impossible that process happens without prior demand
          # we should send at least one item.
          # FIXME potential race condition
          {{:value, item}, new_cache} = :queue.out(new_cache)

          {:ok, [
            {:buffer, {:source, item}}
          ], %{state | cache: new_cache}}
        end
      end

  ## See also

  * `Membrane.Element.Manager.Base.Mixin.CommonBehaviour` - for more callbacks.
  """

  use Membrane.Element.Manager.Log
  use Membrane.Element.Manager.Common
  alias Membrane.Element.Manager.{Action, State, Common}
  alias Membrane.PullBuffer
  use Membrane.Helper

  # Type that defines a single action that may be returned from handle_*
  # callbacks.
  @type callback_action_t ::
    {:buffer, {Membrane.Pad.name_t, Membrane.Buffer.t}} |
    {:caps, {Membrane.Pad.name_t, Membrane.Caps.t}} |
    {:event, {Membrane.Pad.name_t, Membrane.Event.t}} |
    {:demand, Membrane.Pad.name_t} |
    {:demand, {Membrane.Pad.name_t, pos_integer}} |
    {:message, Membrane.Message.t}

  # Type that defines list of actions that may be returned from handle_*
  # callbacks.
  @type callback_actions_t :: [] | [callback_action_t]

  # Type that defines all valid return values from callbacks.
  @type callback_return_t ::
    {:ok, {callback_actions_t, any}} |
    {:error, {any, any}}


  @doc """
  Callback invoked when Element.Manager is receiving information about new caps for
  given pad.

  The arguments are:

  * name of the pad receiving a event,
  * new caps of this pad,
  """
  @callback handle_caps(Membrane.Pad.name_t, any) ::
    callback_return_t


  @doc """
  Callback that is called when buffer should be produced by the source.

  It will be called only for pads in the pull mode, as in their case demand
  is triggered by the sinks.

  For pads in the push mode, Element.Manager should generate buffers without this
  callback. Example scenario might be reading a stream over TCP, waiting
  for incoming packets that will be delivered to the PID of the element,
  which will result in calling `handle_other/2`, which can return value that
  contains the `:buffer` action.

  It is safe to use blocking reads in the filter. It will cause limiting
  throughput of the pipeline to the capability of the source.

  The arguments are:

  * name of the pad receiving a demand request,
  * current caps of this pad,
  * current element's state.
  """
  @callback handle_demand(Membrane.Pad.name_t, any) ::
    callback_return_t


  @doc """
  Callback that is called when event arrives.

  It will be called both for events flowing upstream and downstream.

  The arguments are:

  * name of the pad receiving a event,
  * current caps of this pad,
  * event,
  * current Element.Manager state.
  """
  @callback handle_event(Membrane.Pad.name_t, Membrane.Event.t, any) ::
    callback_return_t


  @doc """
  Callback invoked when Element.Manager is receiving message of other kind.

  The arguments are:

  * message,
  * current element's sate.
  """
  @callback handle_other(any, any) ::
    callback_return_t


  @doc """
  Callback invoked when Element.Manager is supposed to start playing. It will receive
  Element.Manager state.

  This is moment when you should start generating buffers if there're any
  pads in the push mode.
  """
  @callback handle_play(any) ::
    callback_return_t


  @doc """
  Callback invoked when Element.Manager is prepared. It will receive the previous
  Element.Manager state.

  Normally this is the place where you will allocate most of the resources
  used by the Element.Manager. For example, if your Element.Manager opens a file, this is
  the place to try to actually open it and return error if that has failed.

  Such resources should be released in `handle_stop/1`.
  """
  @callback handle_prepare(:stopped | :playing, any) ::
    callback_return_t


  @doc """
  Callback that is called when buffer should be processed by the filter.

  It is safe to use blocking writes in the filter. It will cause limiting
  throughput of the pipeline to the capability of the filter.

  The arguments are:

  * name of the pad receiving a buffer,
  * current caps of this pad,
  * buffer,
  * current element's state.
  """
  @callback handle_process(Membrane.Pad.name_t, Membrane.Buffer.t, any) ::
    callback_return_t


  @doc """
  Callback invoked when Element.Manager is supposed to stop playing. It will receive
  Element.Manager state.

  Normally this is the place where you will release most of the resources
  used by the Element.Manager. For example, if your Element.Manager opens a file, this is
  the place to close it.
  """
  @callback handle_stop(any) ::
    callback_return_t


  # Private API

  def handle_action({:buffer, {pad_name, buffers}}, cb, _params, state), do:
    Action.send_buffer pad_name, buffers, cb, state

  def handle_action({:caps, {pad_name, caps}}, _cb, _params, state), do:
    Action.send_caps(pad_name, caps, state)

  def handle_action({:forward, pads}, :handle_caps, %{caps: caps} = params, state)
  when is_list pads
  do
    pads |> Helper.Enum.reduce_with(state, fn pad, st ->
      handle_action {:caps, {pad, caps}}, :handle_caps, params, st end)
  end

  def handle_action({:forward, pads}, :handle_event, %{event: event} = params, state)
  when is_list pads
  do
    pads |> Helper.Enum.reduce_with(state, fn pad, st ->
      handle_action {:event, {pad, event}}, :handle_event, params, st end)
  end

  def handle_action({:forward, :all}, cb, params, state)
  when cb in [:handle_caps, :handle_event]
  do
    dir = case {cb, params} do
        {:handle_caps, _} -> :source
        {:handle_event, %{direction: :sink}} -> :source
        {:handle_event, %{direction: :source}} -> :sink
      end
    pads = state |> State.get_pads_data(dir) |> Map.keys
    handle_action {:forward, pads}, cb, params, state
  end

  def handle_action({:demand, pad_name}, :handle_demand, src_name, state)
  when is_atom pad_name do
    handle_action({:demand, {pad_name, 1}}, :handle_demand, src_name, state)
  end

  def handle_action({:demand, {pad_name, size}}, :handle_demand, src_name, state)
  when is_integer size do
    handle_action({:demand, {pad_name, src_name, size}}, :handle_demand, nil, state)
  end

  def handle_action({:demand, {pad_name, src_name, size}}, cb, _params, state)
  when size > 0 do
    Action.handle_demand(pad_name, src_name, size, cb, state)
  end

  def handle_action({:demand, {pad_name, _src_name, 0}}, cb, _params, state) do
    debug """
      Ignoring demand of size of 0 requested by callback #{inspect cb}
      on pad #{inspect pad_name}.
      """, state
    {:ok, state}
  end

  def handle_action({:demand, {pad_name, _src_name, size}}, cb, _params, _state)
  when size < 0 do
    raise """
      Callback #{inspect cb} requested demand of invalid size of #{size}
      on pad #{inspect pad_name}. Demands' sizes should be positive (0-sized
      demands are ignored).
      """
  end

  def handle_action({:self_demand, pad_name}, cb, params, state)
  when is_atom(pad_name)
  do
    handle_action {:self_demand, {pad_name, 1}}, cb, params, state
  end

  def handle_action({:self_demand, {pad_name, size}}, cb, params, state) do
    handle_action {:demand, {pad_name, nil, size}}, cb, params, state
  end

  def handle_action(action, callback, params, state) do
    available_actions = [
        "{:buffer, {pad_name, buffers}}",
        "{:caps, {pad_name, caps}}",
        ["{:demand, pad_name}", "{:demand, {pad_name, size}}"]
          |> (provided that: callback == :handle_demand),
        "{:demand, {pad_name, src_name, size}",
        "{:self_demand, pad_name}",
        "{:self_demand, {pad_name, size}}",
        ["{:forward, pads}"]
          |> (provided that: callback in [:handle_caps, :handle_event]),
      ] ++ Common.available_actions
    handle_invalid_action action, callback, params, available_actions, __MODULE__, state
  end

  def handle_demand(pad_name, size, state) do
    {:ok, {total_size, state}} = state
      |> State.get_update_pad_data(:source, pad_name, :demand, &{:ok, {&1+size, &1+size}})
    cond do
      total_size <= 0 ->
        debug """
          Demand handler: not executing handle_demand, as demand is not greater than 0,
          demand: #{inspect total_size}
          """, state
        {:ok, state}

      state |> State.get_pad_data(:source, pad_name, :eos) ->
        debug """
          Demand handler: not executing handle_demand, as EoS has already been sent
          """, state
        {:ok, state}
      true ->
        %{caps: caps, options: %{other_demand_in: demand_in}} =
            state |> State.get_pad_data!(:source, pad_name)
        params = %{caps: caps}
        exec_and_handle_callback(
          :handle_demand, pad_name, [pad_name, total_size, demand_in, params], state)
            |> or_warn_error("""
              Demand arrived from pad #{inspect pad_name}, but error happened while
              handling it.
              """, state)
    end
  end

  def handle_self_demand(pad_name, src_name, buf_cnt, state) do
    {:ok, state} = state |> update_sink_self_demand(pad_name, src_name, & {:ok, &1 + buf_cnt})
    handle_process_pull(pad_name, src_name, buf_cnt, state)
      |> or_warn_error("""
        Demand of size #{inspect buf_cnt} on sink pad #{inspect pad_name}
        was raised, and handle_process was called, but an error happened.
        """, state)
  end

  def handle_buffer(:push, pad_name, buffers, state) do
    handle_process_push pad_name, buffers, state
  end

  def handle_buffer(:pull, pad_name, buffers, state) do
    {:ok, state} = state
      |> State.update_pad_data(:sink, pad_name, :buffer, & &1 |> PullBuffer.store(buffers))
    with \
      {:ok, state} <- check_and_handle_process(pad_name, state),
      {:ok, state} <- check_and_handle_demands(pad_name, state),
    do: {:ok, state}
  end

  def handle_process_push(pad_name, buffers, state) do
    params = %{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}
    exec_and_handle_callback(:handle_process, [pad_name, buffers, params], state)
      |> or_warn_error("Error while handling process", state)
  end

  def handle_process_pull(pad_name, src_name, buf_cnt, state) do
    with \
      {:ok, {out, state}} <- state |> State.get_update_pad_data(:sink, pad_name, :buffer, & &1 |> PullBuffer.take(buf_cnt)),
      {:out, {_, data}} <- (if out == {:empty, []} do {:empty_pb, state} else {:out, out} end),
      {:ok, state} <- data |> Helper.Enum.reduce_with(state, fn v, st ->
        handle_pullbuffer_output pad_name, src_name, v, st
      end)
    do
      :ok = send_dumb_demand_if_demand_positive_and_pullbuffer_nonempty(
        pad_name, src_name, state)
      {:ok, state}
    else
      {:empty_pb, state} -> {:ok, state}
      {:error, reason} -> warn_error "Error while handling process", reason, state
    end
  end

  defp handle_pullbuffer_output(pad_name, src_name, {:buffers, b, buf_cnt}, state) do
    {:ok, state} = state |> update_sink_self_demand(pad_name, src_name, & {:ok, &1 - buf_cnt})
    params = %{
        caps: state |> State.get_pad_data!(:sink, pad_name, :caps),
        source: src_name,
        source_caps: state |> State.get_pad_data!(:sink, pad_name, :caps),
      }
    exec_and_handle_callback :handle_process, [pad_name, b, params], state
  end
  defp handle_pullbuffer_output(pad_name, _src_name, v, state), do:
    Common.handle_pullbuffer_output(pad_name, v, state)

  defp send_dumb_demand_if_demand_positive_and_pullbuffer_nonempty(
    _pad_name, nil = _src_name, _state), do: :ok
  defp send_dumb_demand_if_demand_positive_and_pullbuffer_nonempty(
    pad_name, src_name, state) do
    if (
      state
        |> State.get_pad_data!(:sink, pad_name, :buffer)
        |> PullBuffer.empty? |> Kernel.!
      &&
        state |> State.get_pad_data!(:source, src_name, :demand) > 0
    ) do
      debug """
        handle_process did not produce expected amount of buffers, despite
        PullBuffer being not empty. Trying executing handle_demand again.
        """, state
      send self(), {:membrane_demand, [0, src_name]}
    end
    :ok
  end

  defdelegate handle_caps(mode, pad_name, caps, state), to: Common
  defdelegate handle_event(mode, dir, pad_name, event, state), to: Common

  def handle_new_pad(name, direction, params, state), do:
    Common.handle_new_pad(name, direction, [name, direction, params], state)

  def handle_pad_added(name, direction, state), do:
    Common.handle_pad_added([name, direction], state)

  defp check_and_handle_process(pad_name, state) do
    demand = state |> State.get_pad_data!(:sink, pad_name, :self_demand)
    if demand > 0 do
      handle_process_pull pad_name, nil, demand, state
    else
      {:ok, state}
    end
  end

  defp check_and_handle_demands(pad_name, state) do
    state
      |> State.get_pads_data(:source)
      |> Helper.Enum.reduce_with(state, fn {name, _data}, st ->
          handle_demand name, 0, st
        end)
      |> or_warn_error("""
        New buffers arrived to pad #{inspect pad_name}, and Membrane tried
        to execute handle_demand and then handle_process for each unsupplied
        demand, but an error happened.
        """, state)
  end

  defp update_sink_self_demand(state, pad_name, nil, f), do:
    state |> State.update_pad_data(:sink, pad_name, :self_demand, f)

  defp update_sink_self_demand(state, _pad_name, _src, _f), do: {:ok, state}

end
