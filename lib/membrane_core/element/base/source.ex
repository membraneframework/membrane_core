defmodule Membrane.Element.Base.Source do
  @moduledoc """
  Base module to be used by all elements that are sources, in other words,
  elements that produce the buffers. Some examples might be: a file reader,
  a sound card input.

  ## Callbacks

  As for all base elements in the Membrane Framework, lifecycle of sinks is
  defined by set of callbacks. All of them have names with the `handle_` prefix.
  They are used to define reaction to certain events that happen during runtime,
  and indicate what actions frawork should undertake as a result, besides
  executing element-specific code.

  ## Actions

  All callbacks have to return a value.

  If they were successful they return `{:ok, actions, new_state}` tuple,
  where `actions` is a list of actions to be undertaken by the framework after
  the callback has finished its execution.

  Each action may be one of the following:

  * `{:buffer, {pad_name, buffer}}` - it will cause sending given buffer
    from pad of given name to its peer.
  * `{:caps, {pad_name, caps}}` - it will cause sending new caps for pad of
    given name.
  * `{:event, {pad_name, event}}` - it will cause sending given event
    from pad of given name to its peer.
  * `{:message, message}` - it will cause sending given message to the element's
    message bus (usually a pipeline) if any is defined,

  ## Demand

  If element has source pads in the pull mode, the demand will be triggered
  by sinks. The `handle_demand/2` callback will be then invoked but
  should not return more than one buffer per one `handle_demand/2` call.
  In such case, if element is holding more data than for one buffer,
  the remaining data should remain cached in the element's state and released
  upon next `handle_demand/2`.

  If element has source pads in the push mode, it is allowed to generate
  buffers at any time.

  ## Example

  The simplest possible source element that has pad working in the pull mode,
  looks like the following:

      defmodule Membrane.Element.Sample.Source do
        use Membrane.Element.Base.Source

        def_known_source_pads %{
          :source => {:always, :pull, :any}
        }

        # Private API

        @doc false
        def handle_demand(_pad, state) do
          # Produce one buffer in response to demand
          {:ok, [
            {:buffer, {:source, %Membrane.Buffer{payload: "test"}}}
          ], state}
        end
      end

  ## See also

  * `Membrane.Element.Base.Mixin.CommonBehaviour` - for more callbacks.
  """

  use Membrane.Mixins.Log, tags: :core
  alias Membrane.Element.{Action, Common, State}
  use Membrane.Element.Common


  # Type that defines a single action that may be returned from handle_*
  # callbacks.
  @type callback_action_t ::
    {:buffer, {Membrane.Pad.name_t, Membrane.Buffer.t}} |
    {:caps, {Membrane.Pad.name_t, Membrane.Caps.t}} |
    {:event, {Membrane.Pad.name_t, Membrane.Event.t}} |
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
  * current element's state.
  """
  @callback handle_demand(Membrane.Pad.name_t, any) ::
    callback_return_t


  @doc """
  Callback that is called when event arrives.

  It will be called for events flowing upstream from the subsequent elements.

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
  Callback invoked when element is supposed to stop playing. It will receive
  element state.

  Normally this is the place where you will release most of the resources
  used by the element. For example, if your element opens a file, this is
  the place to close it.
  """
  @callback handle_stop(any) ::
    callback_return_t


  # Private API

  def handle_demand(pad_name, size, state) do
    {:ok, {stored_size, state}} = state
      |> State.get_update_pad_data(:source, pad_name, :demand, &{:ok, {&1, &1+size}})
    if stored_size + size > 0 do
      %{caps: caps, options: %{other_demand_in: demand_in}} =
          state |> State.get_pad_data!(:source, pad_name)
      params = %{caps: caps}
      exec_and_handle_callback(
        :handle_demand, [pad_name, size + min(0, stored_size), demand_in, params], state)
          |> or_warn_error("""
            Demand arrived from pad #{inspect pad_name}, but error happened while
            handling it.
            """)
    else
      debug """
        Demand handler: not executing handle_demand, as demand is not
        greater than 0
        """
      {:ok, state}
    end
  end

  @doc false

  def handle_action({:buffer, {pad_name, buffer}}, _cb, _params, state), do:
    Action.send_buffer(pad_name, buffer, state)

  def handle_action({:caps, {pad_name, caps}}, _params, _cb, state), do:
    Action.send_caps(pad_name, caps, state)

    def handle_action(action, callback, params, state) do
      available_actions = [
          "{:buffer, {pad_name, buffers}}",
          "{:caps, {pad_name, caps}}",
        ] ++ Common.available_actions
      handle_invalid_action action, callback, params, available_actions, __MODULE__, state
    end

  def handle_event(mode, :source, pad_name, event, state), do:
    Common.handle_event(mode, :source, pad_name, event, state)

  def handle_link(pad_name, :source, pid, other_name, props, state), do:
    Common.handle_link(pad_name, :source, pid, other_name, props, state)

  def handle_new_pad(name, :source, params, state), do:
    Common.handle_new_pad(name, :source, [name, params], state)

  def handle_pad_added(name, :sink, state), do:
    Common.handle_pad_added([name], state)

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SourceBehaviour


      @doc """
      Returns module on which this element is based.
      """
      @spec base_module() :: module
      def base_module, do: Membrane.Element.Base.Source


      # Default implementations

      @doc false
      def handle_new_pad(_pad, _params, state), do: {:error, :adding_pad_unsupported}

      @doc false
      def handle_pad_added(_pad, state), do: {:ok, state}

      @doc false
      def handle_pad_removed(_pad, state), do: {:ok, state}

      @doc false
      def handle_demand1(_pad, _params, state), do:
        {{:error, :handle_demand_not_implemented}, state}

      @doc false
      def handle_demand(pad, size, :buffers, params, state) do
        1..size |> Common.reduce_something1_results(state, fn _, st ->
            handle_demand1 pad, params, st
          end)
      end
      def handle_demand(_pad, _size, _unit, _params, state), do:
        {{:error, :handle_demand_not_implemented}, state}

      @doc false
      def handle_event(_pad, _event, _params, state), do: {:ok, state}

      @doc false
      def handle_other(_message, state), do: {:ok, state}

      @doc false
      def handle_play(state), do: {:ok, state}

      @doc false
      def handle_prepare(_previous_playback_state, state), do: {:ok, state}

      @doc false
      def handle_stop(state), do: {:ok, state}


      defoverridable [
        handle_new_pad: 3,
        handle_pad_added: 2,
        handle_pad_removed: 2,
        handle_demand1: 3,
        handle_demand: 5,
        handle_event: 4,
        handle_other: 2,
        handle_play: 1,
        handle_prepare: 2,
        handle_stop: 1,
      ]
    end
  end
end
