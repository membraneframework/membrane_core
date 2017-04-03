defmodule Membrane.Element.Base.Sink do
  @moduledoc """
  Base module to be used by all elements that are sinks, in other words,
  elements that just consume the buffers. Some examples might be: a file writer,
  a sound card output.

  ## Callbacks

  As for all base elements in the Membrane Framework, lifecycle of sinks is
  defined by set of callbacks. All of them have names with the `handle_` prefix.
  They are used to define reaction to certain events that happen during runtime,
  and indicate what actions frawork should undertake as a result, besides
  executing element-specific code.

  Sinks have a callback that will be core to their operations in all sane cases:
  `handle_write/3` which gets called when data is available and should be written.

  ## Actions

  All callbacks have to return a value.

  If they were successful they return `{:ok, actions, new_state}` tuple,
  where `actions` is a list of actions to be undertaken by the framework after
  the callback has finished its execution.

  They are combination of actions that can be returned by sources and sinks,
  and each action may be one of the following:

  * `{:demand, pad_name}` - it will cause sending request for more buffers to
    the pad of given name.
  * `{:event, {pad_name, event}}` - it will cause sending given event
    from pad of given name to its peer.
  * `{:message, message}` - it will cause sending given message to the element's
    message bus (usually a pipeline) if any is defined.

  ## Demand

  If element has pads in the pull mode, in the tuple returned upon succesful
  execution of the `handle_write/3` callback it should return at least one
  `:demand` action. In such cases sinks drive the demand, to avoid generating
  too much data by the sources unless its necessary, this is used to tell the
  framework whether it should tell upstream elements to generate more buffers
  or not, with the following exception.

  ### Third-party triggers and buffering

  There are elements that are callback based, e.g. they rely on third-party
  library that have their own callbacks signalling when it is ready to consume
  more data, or sound card that triggers need for more buffers. They usually
  do this in the NIF code, so the only potential way of communicating this
  need back to the Elixir code is by sending a message from the NIF, but even
  if the element would have responded with the data immediately, it would be
  extremely hard to pass it back to the callback, especially given that the
  common practice is that such libraries expect their callback to execute very
  quickly.

  The pattern in such scenario is to send message from such element once the
  buffer was consumed, use `handle_other/2` callback to capture it and return
  `:demand` as an action only when it has happened.

  Please note that in such scenario you usually want to keep at least one
  buffer in the element (and in practice, more than one) so when callback gets
  called, data is immediately available. Then `:demand` action acts rather as an
  indicator that buffer was consumed, than then the sink is already drained,
  so next buffer will be already generated once next callback is triggered.
  NIF-based elements might want to use `MembraneRingBuffer` for lock-free
  internal cache for buffers from the [membrane-common-c](https://www.github.com/membraneframework/membrane-common-c)
  package. Pure Elixir-based elements may rely e.g. on the `:queue` Erlang
  module.


  ## Examples

  ### Pull mode

  The simplest possible sink element that works in the pull mode may look like
  the following:

      defmodule Membrane.Element.Sample.Sink do
        use Membrane.Element.Base.Sink

        def_known_sink_pads %{
          :sink => {:always, :pull, :any}
        }

        # Private API

        @doc false
        def handle_write(_pad, buffer, state) do
          # Consume one buffer and say upstream we want more as in the pull
          # mode it is sink deciding when to get more buffers.

          IO.puts inspect(buffer)
          {:ok, [
            {:demand, :sink},
          ], state}
        end
      end

  ### Push mode

  The simplest possible sink element that works in the push mode may look like
  the following:

      defmodule Membrane.Element.Sample.Sink do
        use Membrane.Element.Base.Sink

        def_known_sink_pads %{
          :sink => {:always, :push, :any}
        }

        # Private API

        @doc false
        def handle_write(_pad, buffer, state) do
          # Consume one buffer and do nothing as it is upstream element that
          # decides when to generate next buffer in the push mode.

          IO.puts inspect(buffer)
          {:ok, state}
        end
      end

  ## See also

  * `Membrane.Element.Base.Mixin.CommonBehaviour` - for more callbacks.
  """

  alias Membrane.Element.Action


  # Type that defines a single action that may be returned from handle_*
  # callbacks.
  @type callback_action_t ::
    {:demand, Membrane.Pad.name_t} |
    {:message, Membrane.Message.t}

  # Type that defines list of actions that may be returned from handle_*
  # callbacks.
  @type callback_actions_t :: [] | [callback_action_t]

  # Type that defines all valid return values from callbacks that are not
  # triggered by pads so they cannot indicate demand.
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
  Callback that is called when event arrives.

  It will be called for events flowing downstream from previous elements.

  The arguments are:

  * name of the pad receiving a event,
  * event,
  * current element state.
  """
  @callback handle_event(Membrane.Pad.name_t, Membrane.Event.t, any) ::
    callback_return_t


  @doc """
  Callback invoked when element is receiving message of other kind.

  The arguments are:

  * message,
  * current element's state.
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
  Callback invoked when element is supposed to stop playing. It will receive
  element state.

  Normally this is the place where you will release most of the resources
  used by the element. For example, if your element opens a file, this is
  the place to close it.
  """
  @callback handle_stop(any) ::
    callback_return_t


  @doc """
  Callback that is called when buffer should be written by the sink.

  It is safe to use blocking writes in the sink. It will cause limiting
  throughput of the pipeline to the capability of the sink.

  The arguments are:

  * name of the pad receiving a buffer,
  * buffer,
  * current element's state.
  """
  @callback handle_write(Membrane.Pad.name_t, Membrane.Buffer.t, any) ::
    callback_return_t


  # Private API

  @doc false
  @spec handle_actions(callback_actions_t, State.t) ::
    {:ok, State.t} |
    {:error, {any, State.t}}
  def handle_actions([], state), do: {:ok, state}

  def handle_actions([{:demand, pad_name}|tail], state) do
    case Action.handle_demand(pad_name, state) do
      {:ok, state} ->
        handle_actions(tail, state)

      {:error, reason} ->
        {:error, {reason, state}}
    end
  end

  def handle_actions([{:event, {pad_name, event}}|tail], state) do
    case Action.handle_event(pad_name, event, state) do
      {:ok, state} ->
        handle_actions(tail, state)

      {:error, reason} ->
        {:error, {reason, state}}
    end
  end

  def handle_actions([{:message, message}|tail], state) do
    case Action.handle_message(message, state) do
      {:ok, state} ->
        handle_actions(tail, state)

      {:error, reason} ->
        {:error, {reason, state}}
    end
  end

  def handle_actions([other|_tail], _state) do
    raise """
    Sinks' callback replies are expected to be one of:

        {:ok, {actions, state}}
        {:error, {reason, state}}

    where actions is a list where each item is one action in one of the
    following syntaxes:

        {:demand, pad_name}
        {:message, message}

    for example:

        {:ok, [
          {:demand, :sink}
        ], %{key: "val"}}

    but got action #{inspect(other)}.

    This is probably a bug in the element, check if its callbacks return values
    in the right format.
    """
  end


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour


      @doc """
      Returns module on which this element is based.
      """
      @spec base_module() :: module
      def base_module, do: Membrane.Element.Base.Sink


      # Default implementations

      @doc false
      def handle_caps(_pad, state), do: {:ok, {[], state}}

      @doc false
      def handle_event(_pad, _event, state), do: {:ok, {[], state}}

      @doc false
      def handle_other(_message, state), do: {:ok, {[], state}}

      @doc false
      def handle_play(state), do: {:ok, {[], state}}

      @doc false
      def handle_prepare(_previous_playback_state, state), do: {:ok, {[], state}}

      @doc false
      def handle_stop(state), do: {:ok, {[], state}}

      @doc false
      def handle_write(_pad, _buffer, state), do: {:ok, {[], state}}


      defoverridable [
        handle_caps: 2,
        handle_event: 3,
        handle_other: 2,
        handle_play: 1,
        handle_prepare: 2,
        handle_stop: 1,
        handle_write: 3,
      ]
    end
  end
end
