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

  use Membrane.Mixins.Log, tags: :core
  use Membrane.Element.Common
  alias Membrane.Element.{State, Action, Common}
  alias Membrane.PullBuffer
  alias Membrane.Helper


  # Type that defines a single action that may be returned from handle_*
  # callbacks.
  @type callback_action_t ::
    {:demand, Membrane.Pad.name_t} |
    {:demand, {Membrane.Pad.name_t, pos_integer}} |
    {:event, {Membrane.Pad.name_t, Membrane.Event.t}} |
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


  def handle_action({:demand, pad_name}, cb, params, state)
  when is_atom pad_name do
    handle_action({:demand, {pad_name, 1}}, cb, params, state)
  end

  def handle_action({:demand, {pad_name, size}}, cb, _params, state)
  when size > 0 do
    Action.handle_demand(pad_name, size, cb, state)
  end

  def handle_action({:demand, {pad_name, 0}}, cb, _params, state) do
    debug """
      Ignoring demand of size of 0 requested by callback #{inspect cb}
      on pad #{inspect pad_name}.
      """
    {:ok, state}
  end

  def handle_action({:demand, {pad_name, size}}, cb, _params, _state)
  when size < 0 do
    raise """
      Callback #{inspect cb} requested demand of invalid size of #{size}
      on pad #{inspect pad_name}. Demands' sizes should be positive (0-sized
      demands are ignored).
      """
  end

  def handle_action(action, callback, params, state) do
    available_actions = [
        "{:demand, pad_name}",
        "{:demand, {pad_name, size}}",
      ] ++ Common.available_actions
    handle_invalid_action action, callback, params, available_actions, __MODULE__, state
  end

  def handle_self_demand pad_name, _src_name, buf_cnt, state do
    {:ok, state} = state
      |> State.update_pad_data(:sink, pad_name, :self_demand, & {:ok, &1 + buf_cnt})
    handle_write(:pull, pad_name, state)
      |> or_warn_error("""
        Demand of size #{inspect buf_cnt} on pad #{inspect pad_name}
        was raised, and handle_write was called, but an error happened.
        """)
  end

  def handle_buffer(:push, pad_name, buffer, state), do:
    handle_write(:push, pad_name, buffer, state)

  def handle_buffer(:pull, pad_name, buffer, state) do
    {:ok, state} = state
      |> State.update_pad_data(:sink, pad_name, :buffer, & &1 |> PullBuffer.store(buffer))
    check_and_handle_write(pad_name, state)
      |> or_warn_error("""
        New buffer arrived:
        #{inspect buffer}
        and Membrane tried to execute handle_demand and then handle_write
        for each unsupplied demand, but an error happened.
        """)
  end

  def handle_write(:push, pad_name, buffer, state) do
    params = %{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}
    exec_and_handle_callback(:handle_write, [pad_name, buffer, params], state)
      |> or_warn_error("Error while handling write")
  end

  def handle_write(:pull, pad_name, state) do
    with \
      {:ok, {out, state}} <- state
        |> State.get_update_pad_data(:sink, pad_name, fn %{self_demand: demand, buffer: pb} = data ->
            with {:ok, {out, npb}} <- PullBuffer.take(pb, demand)
            do {:ok, {out, %{data | buffer: npb}}}
            end
          end),
      {:out, {_, data}} <- (if out == {:empty, []} do {:empty_pb, state} else {:out, out} end),
      {:ok, state} <- data |> Helper.Enum.reduce_with(state, fn v, st ->
          handle_pullbuffer_output pad_name, v, st
        end)
    do {:ok, state}
    else
      {:empty_pb, state} -> {:ok, state}
      {:error, reason} -> warn_error "Error while handling write", reason
    end
  end

  defp handle_pullbuffer_output(pad_name, {:buffers, b, buf_cnt}, state) do
    {:ok, state} = state |>
      State.update_pad_data(:sink, pad_name, :self_demand, & {:ok, &1 - buf_cnt})
    params = %{caps: state |> State.get_pad_data!(:sink, pad_name, :caps)}
    debug "Executing handle_write with buffers #{inspect b}"
    exec_and_handle_callback :handle_write, [pad_name, b, params], state
  end
  defp handle_pullbuffer_output(pad_name, v, state), do:
    Common.handle_pullbuffer_output(pad_name, v, state)

  defdelegate handle_caps(mode, pad_name, caps, state), to: Common

  def handle_event(mode, :sink, pad_name, event, state), do:
    Common.handle_event(mode, :sink, pad_name, event, state)

  def handle_link(pad_name, :sink, pid, other_name, props, state), do:
    Common.handle_link(pad_name, :sink, pid, other_name, props, state)

  def handle_new_pad(name, :sink, params, state), do:
    Common.handle_new_pad(name, :sink, [name, params], state)

  def handle_pad_added(name, :sink, state), do:
    Common.handle_pad_added([name], state)

  defp check_and_handle_write(pad_name, state) do
    if State.get_pad_data!(state, :sink, pad_name, :self_demand) > 0 do
      handle_write :pull, pad_name, state
    else
      {:ok, state}
    end
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
      def handle_new_pad(_pad, _params, state), do: {:error, :adding_pad_unsupported}

      @doc false
      def handle_pad_added(_pad, state), do: {:ok, state}

      @doc false
      def handle_pad_removed(_pad, state), do: {:ok, state}

      @doc false
      def handle_caps(_pad, _caps, _params, state), do: {:ok, state}

      @doc false
      def handle_write1(_pad, _buffer, _params, state), do: {:ok, state}

      @doc false
      def handle_write(pad, buffers, params, state) do
        buffers |> Common.reduce_something1_results(state, fn buf, st ->
            handle_write1 pad, buf, params, st
          end)
      end


      defoverridable [
        handle_new_pad: 3,
        handle_pad_added: 2,
        handle_pad_removed: 2,
        handle_caps: 4,
        handle_write: 4,
        handle_write1: 4,
      ]
    end
  end
end
