defmodule Membrane.Parent do
  alias Membrane.{Child, Notification, Pad, Parent}
  alias Membrane.Core.{Bin, CallbackHandler, Pipeline}

  @type internal_state_t :: map | struct

  @type state_t :: Bin.State.t() | Pipeline.State.t()

  @typedoc """
  Type that defines all valid return values from most callbacks.
  """
  @type callback_return_t ::
          CallbackHandler.callback_return_t(Parent.Action.t(), internal_state_t())

  @doc """
  Callback invoked when bin transition from `:stopped` to `:prepared` state has finished,
  that is all of its elements are prepared to enter `:playing` state.
  """
  @callback handle_stopped_to_prepared(state :: internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when bin transition from `:playing` to `:prepared` state has finished,
  that is all of its elements are prepared to be stopped.
  """
  @callback handle_playing_to_prepared(state :: internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when bin is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_prepared_to_playing(state :: internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when bin is in `:playing` state, i.e. all its elements
  are in this state.
  """
  @callback handle_prepared_to_stopped(state :: internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when a notification comes in from an element.
  """
  @callback handle_notification(
              notification :: Notification.t(),
              element :: Child.name_t(),
              state :: internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when bin receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving ticks from timer, data sent from NIFs or other stuff.
  """
  @callback handle_other(message :: any, state :: internal_state_t()) :: callback_return_t

  @doc """
  Callback invoked when pipeline's element receives `Membrane.Event.StartOfStream` event.
  """
  @callback handle_element_start_of_stream(
              {Child.name_t(), Pad.ref_t()},
              state :: internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when pipeline's element receives `Membrane.Event.EndOfStream` event.
  """
  @callback handle_element_end_of_stream(
              {Child.name_t(), Pad.ref_t()},
              state :: internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when `Membrane.Bin.Spec` is linked and in the same playback
  state as bin.

  Spec can be started from `c:handle_init/1` callback or as
  `t:Membrane.Core.Parent.Action.spec_action_t/0` action.
  """
  @callback handle_spec_started(
              elements :: [Child.name_t()],
              state :: internal_state_t()
            ) ::
              callback_return_t

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      @impl true
      def handle_stopped_to_prepared(state), do: {:ok, state}

      @impl true
      def handle_playing_to_prepared(state), do: {:ok, state}

      @impl true
      def handle_prepared_to_playing(state), do: {:ok, state}

      @impl true
      def handle_prepared_to_stopped(state), do: {:ok, state}

      @impl true
      def handle_other(_message, state), do: {:ok, state}

      @impl true
      def handle_spec_started(_new_children, state), do: {:ok, state}

      @impl true
      def handle_element_start_of_stream({_element, _pad}, state), do: {:ok, state}

      @impl true
      def handle_element_end_of_stream({_element, _pad}, state), do: {:ok, state}

      defoverridable handle_stopped_to_prepared: 1,
                     handle_playing_to_prepared: 1,
                     handle_prepared_to_playing: 1,
                     handle_prepared_to_stopped: 1,
                     handle_other: 2,
                     handle_spec_started: 2,
                     handle_element_start_of_stream: 2,
                     handle_element_end_of_stream: 2
    end
  end
end
