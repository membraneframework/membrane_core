defmodule Membrane.Core.Element.LifecycleController do
  @moduledoc false

  # Module handling element initialization, termination, playback changes
  # and similar stuff.

  use Bunch

  alias Membrane.Core.{CallbackHandler, Child, Element, Message}
  alias Membrane.{Clock, Element, Sync}
  alias Membrane.Core.{CallbackHandler, Child, Element, Message}
  alias Membrane.Core.Element.{ActionHandler, PlaybackQueue, State}
  alias Membrane.Element.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Logger

  @doc """
  Performs initialization tasks and executes `handle_init` callback.
  """
  @spec handle_init(Element.options_t(), State.t()) :: State.t()
  def handle_init(options, %State{module: module} = state) do
    Membrane.Logger.debug(
      "Initializing element: #{inspect(module)}, options: #{inspect(options)}"
    )

    :ok = Sync.register(state.synchronization.stream_sync)

    clock =
      if Bunch.Module.check_behaviour(module, :membrane_clock?) do
        {:ok, clock} = Clock.start_link()
        clock
      else
        nil
      end

    state = put_in(state.synchronization.clock, clock)
    Message.send(state.parent_pid, :clock, [state.name, clock])

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_init,
        ActionHandler,
        %{},
        [options],
        state
      )

    state
  end

  @spec handle_setup(State.t()) :: State.t()
  def handle_setup(state) do
    require CallbackContext.Setup
    context = &CallbackContext.Setup.from_state/1

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_setup,
        ActionHandler,
        %{context: context},
        [],
        state
      )

    Membrane.Logger.debug("Element initialized")
    Message.send(state.parent_pid, :initialized, state.name)
    %State{state | initialized?: true}
  end

  @spec handle_playing(State.t()) :: State.t()
  def handle_playing(state) do
    Child.PadController.assert_all_static_pads_linked!(state)

    Membrane.Logger.debug("Got play request")
    state = %State{state | playback: :playing}
    require CallbackContext.Play
    context = &CallbackContext.Play.from_state/1

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_playing,
        ActionHandler,
        %{context: context},
        [],
        state
      )

    PlaybackQueue.eval(state)
  end

  @spec handle_terminate_request(State.t()) :: State.t()
  def handle_terminate_request(state) do
    Membrane.Logger.debug("Received terminate request")

    state.pads_data
    |> Map.values()
    |> Enum.filter(&(&1.direction == :input))
    |> Enum.reduce(state, fn %{ref: pad_ref}, state_acc ->
      Element.PadController.generate_eos_if_needed(pad_ref, state_acc)
    end)
  end

  @spec handle_terminate(reason :: any, State.t()) :: :ok
  def handle_terminate(reason, state) do
    Membrane.Logger.debug("Terminating element, reason: #{inspect(reason)}")
    result = state.module.handle_terminate_yolo(reason, state.internal_state)

    if result != :ok do
      Membrane.Logger.warn(
        "`#{inspect(state.module)}.handle_terminate_yolo` callback returned value other than `:ok`"
      )
    end

    :ok
  end

  @doc """
  Handles custom messages incoming to element.
  """
  @spec handle_info(message :: any, State.t()) :: State.t()
  def handle_info(message, state) do
    require CallbackContext.Other
    context = &CallbackContext.Other.from_state/1

    CallbackHandler.exec_and_handle_callback(
      :handle_info,
      ActionHandler,
      %{context: context},
      [message],
      state
    )
  end
end
