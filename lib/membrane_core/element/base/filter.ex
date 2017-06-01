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

  alias Membrane.Element.Action


  # Type that defines a single action that may be returned from handle_*
  # callbacks.
  @type callback_action_t ::
    {:buffer, {Membrane.Pad.name_t, Membrane.Buffer.t}} |
    {:caps, {Membrane.Pad.name_t, Membrane.Caps.t}} |
    {:event, {Membrane.Pad.name_t, Membrane.Event.t}} |
    {:demand, Membrane.Pad.name_t} |
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
  @spec handle_actions(callback_actions_t, atom, State.t) ::
    {:ok, State.t} |
    {:error, {any, State.t}}
  def handle_actions([], _callback, state), do: {:ok, state}

  def handle_actions([{:buffer, {pad_name, buffer}}|tail], callback, state) do
    case Action.handle_buffer(pad_name, buffer, state) do
      {:ok, state} ->
        handle_actions(tail, callback, state)

      {:error, reason} ->
        {:error, {reason, state}}
    end
  end

  def handle_actions([{:caps, {pad_name, caps}}|tail], callback, state) do
    case Action.handle_caps(pad_name, caps, state) do
      {:ok, state} ->
        handle_actions(tail, callback, state)

      {:error, reason} ->
        {:error, {reason, state}}
    end
  end

  def handle_actions([{:demand, pad_name}|tail], callback, state) do
    handle_actions [{:demand, pad_name, 1}|tail], callback, state
  end
  def handle_actions([{:demand, pad_name, size}|tail], callback, state) do
    case Action.handle_demand(pad_name, size, callback, state) do
      {:ok, state} ->
        handle_actions(tail, callback, state)

      {:error, reason} ->
        {:error, {reason, state}}
    end
  end

  def handle_actions([{:event, {pad_name, event}}|tail], callback, state) do
    case Action.handle_event(pad_name, event, state) do
      {:ok, state} ->
        handle_actions(tail, callback, state)

      {:error, reason} ->
        {:error, {reason, state}}
    end
  end

  def handle_actions([{:message, message}|tail], callback, state) do
    case Action.handle_message(message, state) do
      {:ok, state} ->
        handle_actions(tail, callback, state)

      {:error, reason} ->
        {:error, {reason, state}}
    end
  end

  def handle_actions([other|_tail], _callback, _state) do
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
      def handle_demand(_pad, state), do: {:ok, {[], state}}

      @doc false
      def handle_event(_pad, _event, state), do: {:ok, {[], state}}

      @doc false
      def handle_other(_message, state), do: {:ok, {[], state}}

      @doc false
      def handle_play(state), do: {:ok, {[], state}}

      @doc false
      def handle_prepare(_previous_playback_state, state), do: {:ok, {[], state}}

      @doc false
      def handle_process(_pad, _buffer, state), do: {:ok, {[], state}}

      @doc false
      def handle_stop(state), do: {:ok, {[], state}}


      defoverridable [
        handle_caps: 2,
        handle_demand: 2,
        handle_event: 3,
        handle_other: 2,
        handle_play: 1,
        handle_prepare: 2,
        handle_process: 3,
        handle_stop: 1,
      ]
    end
  end
end
