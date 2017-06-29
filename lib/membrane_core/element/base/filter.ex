defmodule Membrane.Element.Base.Filter do
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
  In such case, if upstream element has sent more data than for one buffer,
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

  The simplest possible filter element working in the pull mode may look like
  the following. It gets buffers from upstream (we assume buffers' payload
  are strings), splits them into individual letters and send these individual
  letters as buffers:

      defmodule Membrane.Element.Sample.Filter do
        use Membrane.Element.Base.Filter

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

  * `Membrane.Element.Base.Mixin.CommonBehaviour` - for more callbacks.
  """

  use Membrane.Mixins.Log
  use Membrane.Element.Common
  alias Membrane.Element.{Action, State, Common}
  alias Membrane.PullBuffer
  alias Membrane.Helper

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
  Callback invoked when element is receiving information about new caps for
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

  For pads in the push mode, element should generate buffers without this
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
  * current element state.
  """
  @callback handle_event(Membrane.Pad.name_t, Membrane.Event.t, any) ::
    callback_return_t


  @doc """
  Callback invoked when element is receiving message of other kind.

  The arguments are:

  * message,
  * current element's sate.
  """
  @callback handle_other(any, any) ::
    callback_return_t


  @doc """
  Callback invoked when element is supposed to start playing. It will receive
  element state.

  This is moment when you should start generating buffers if there're any
  pads in the push mode.
  """
  @callback handle_play(any) ::
    callback_return_t


  @doc """
  Callback invoked when element is prepared. It will receive the previous
  element state.

  Normally this is the place where you will allocate most of the resources
  used by the element. For example, if your element opens a file, this is
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
  Callback invoked when element is supposed to stop playing. It will receive
  element state.

  Normally this is the place where you will release most of the resources
  used by the element. For example, if your element opens a file, this is
  the place to close it.
  """
  @callback handle_stop(any) ::
    callback_return_t


  # Private API

  @doc false
  @spec handle_action(callback_action_t, atom, State.t) ::
    {:ok, State.t} |
    {:error, {any, State.t}}

  def handle_action({:buffer, {pad_name, buffers}}, _cb, state), do:
    Action.send_buffer pad_name, buffers, state

  def handle_action({:caps, {pad_name, caps}}, _cb, state), do:
    Action.send_caps(pad_name, caps, state)


  def handle_action({:demand, pad_name}, {:handle_demand, src_name}, state)
  when is_atom pad_name do
    handle_action({:demand, {pad_name, src_name}}, :handle_demand, state)
  end

  def handle_action({:demand, {pad_name, size}}, {:handle_demand, src_name}, state)
  when is_integer size do
    handle_action({:demand, {pad_name, src_name, size}}, :handle_demand, state)
  end

  def handle_action({:demand, {pad_name, src_name}}, cb, state), do:
    handle_action({:demand, {pad_name, src_name, 1}}, cb, state)

  def handle_action({:demand, {pad_name, src_name, size}}, {:handle_demand, _src_name}, state)
  when size > 0 do
    Action.handle_demand(pad_name, src_name, size, :handle_demand, state)
  end

  def handle_action({:demand, {pad_name, src_name, size}}, cb, state)
  when size > 0 do
    Action.handle_demand(pad_name, src_name, size, cb, state)
  end

  def handle_action({:demand, {pad_name, _src_name, 0}}, cb, state) do
    debug """
      Ignoring demand of size of 0 requested by callback #{inspect cb}
      on pad #{inspect pad_name}.
      """
    {:ok, state}
  end

  def handle_action({:demand, {pad_name, _src_name, size}}, cb, _state)
  when size < 0 do
    raise """
      Callback #{inspect cb} requested demand of invalid size of #{size}
      on pad #{inspect pad_name}. Demands' sizes should be positive (0-sized
      demands are ignored).
      """
  end


  def handle_action(other, _cb, _state) do
    raise """
    Filters' callback replies are expected to be one of:

        {:ok, {actions, state}}
        {:error, {reason, state}}

    where actions is a list where each item is one action in one of the
    following syntaxes:

        {:caps, {pad_name, caps}}
        {:demand, pad_name}
        {:buffer, {pad_name, buffer}}
        {:message, message}

    for example:

        {:ok, [
          {:buffer, {:source, Membrane.Event.eos()}}
        ], %{key: "val"}}

    but got action #{inspect(other)}.

    This is probably a bug in the element, check if its callbacks return values
    in the right format.
    """
  end

  def handle_demand(pad_name, size, state) do
    {:ok, {total_size, state}} = state
      |> State.get_update_pad_data!(:source, pad_name, :demand, &{:ok, {&1+size, &1+size}})
    if total_size > 0 do
      Common.exec_and_handle_callback(:handle_demand, {:handle_demand, pad_name}, [pad_name, total_size], state)
        |> orWarnError("""
          Demand arrived from pad #{inspect pad_name}, but error happened while
          handling it.
          """)
    else
      debug """
        Demand handler: not executing handle_demand, as demand is not greater than 0
        """
      {:ok, state}
    end
  end

  def handle_self_demand(pad_name, src_name, buf_cnt, state) do
    handle_process(:pull, pad_name, src_name, buf_cnt, state)
      |> orWarnError("""
        Demand of size #{inspect buf_cnt} on sink pad #{inspect pad_name}
        was raised, and handle_process was called, but an error happened.
        """)
  end

  def handle_buffer(:push, pad_name, buffers, state) do
    with {:ok, state} <- handle_process(:push, pad_name, buffers, state)
    do check_and_handle_demands pad_name, buffers, state
    end
  end

  def handle_buffer(:pull, pad_name, buffers, state) do
    {:ok, state} = state
      |> State.update_pad_data!(:sink, pad_name, :buffer, & &1 |> PullBuffer.store(buffers))
    check_and_handle_demands pad_name, buffers, state
  end

  def handle_process(:push, pad_name, buffers, state) do
    Common.exec_and_handle_callback(:handle_process, [pad_name, buffers], state)
      |> orWarnError("Error while handling process")
  end

  def handle_process(:pull, pad_name, src_name, buf_cnt, state) do
    with \
      {:ok, {out, state}} <- state |> State.get_update_pad_data!(:sink, pad_name, :buffer, & &1 |> PullBuffer.take(buf_cnt)),
      {:out, {_, data}} <- (if out == {:empty, []} do {:empty_pb, state} else {:out, out} end),
      {:ok, state} <- data |> Helper.Enum.reduce_with(state, fn
          {:buffers, b} -> Common.exec_and_handle_callback :handle_process, [pad_name, src_name, b], state
          {:event, e} -> Common.exec_and_handle_callback :handle_event, [pad_name, e], state
        end)
    do
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
          """
        {:ok, {_availability, _direction, _mode, pid}} = state |> State.get_pad_by_name(:source, src_name)
        send pid, {:membrane_demand, 0}
      end
      {:ok, state}
    else
      {:empty_pb, state} -> {:ok, state}
      {:error, reason} -> warnError "Error while handling process", reason
    end
  end

  defdelegate handle_event(mode, dir, pad_name, event, state), to: Common

  defp check_and_handle_demands(pad_name, buffers, %State{source_pads_data: source_pads_data} = state) do
    source_pads_data
      |> Enum.map(fn {src, data} -> {src, data.demand} end)
      |> Helper.Enum.reduce_with(state, fn {name, demand}, st ->
          if demand > 0 do handle_demand name, 0, st else {:ok, st} end
        end)
      |> orWarnError("""
        New buffers arrived to pad #{inspect pad_name}:
        #{inspect buffers}
        and Membrane tried to execute handle_demand and then handle_process
        for each unsupplied demand, but an error happened.
        """)
  end

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SourceBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour


      @doc """
      Returns module on which this element is based.
      """
      @spec base_module() :: module
      def base_module, do: Membrane.Element.Base.Filter


      # Default implementations

      @doc false
      def handle_caps(_pad, state), do: {:ok, {[], state}}

      @doc false
      def handle_demand(_pad, size, state), do: {:ok, {[], state}}

      @doc false
      def handle_event(_pad, _event, state), do: {:ok, {[], state}}

      @doc false
      def handle_other(_message, state), do: {:ok, {[], state}}

      @doc false
      def handle_play(state), do: {:ok, {[], state}}

      @doc false
      def handle_prepare(_previous_playback_state, state), do: {:ok, {[], state}}

      @doc false
      def handle_process1(_pad, _demand_src, _buffer, state), do: {:ok, {[], state}}

      @doc false
      def handle_process(pad, demand_src, buffers, state) do
        with {:ok, {actions, state}} <- buffers
          |> Membrane.Helper.Enum.map_reduce_with(state, &handle_process1(pad, demand_src, &1, &2))
        do {:ok, {actions |> List.flatten, state}}
        end
      end

      @doc false
      def handle_stop(state), do: {:ok, {[], state}}


      defoverridable [
        handle_caps: 2,
        handle_demand: 3,
        handle_event: 3,
        handle_other: 2,
        handle_play: 1,
        handle_prepare: 2,
        handle_process: 4,
        handle_process1: 4,
        handle_stop: 1,
      ]
    end
  end
end
