defmodule Membrane.Core.Element.LifecycleController do
  @moduledoc false

  # Module handling element initialization, termination, playback changes
  # and similar stuff.

  use Bunch

  alias Membrane.{Clock, Element, Sync}
  alias Membrane.Core.{CallbackHandler, Element, Message, SubprocessSupervisor}

  alias Membrane.Core.Element.{
    ActionHandler,
    CallbackContext,
    EffectiveFlowController,
    PlaybackQueue,
    State
  }

  require Membrane.Core.Message
  require Membrane.Logger

  @doc """
  Performs initialization tasks and executes `handle_init` callback.
  """
  @spec handle_init(Element.options(), State.t()) :: State.t()
  def handle_init(options, %State{module: module} = state) do
    Membrane.Logger.debug(
      "Initializing element: #{inspect(module)}, options: #{inspect(options)}"
    )

    :ok = Sync.register(state.synchronization.stream_sync)

    clock =
      if Bunch.Module.check_behaviour(module, :membrane_clock?) do
        {:ok, clock} =
          SubprocessSupervisor.start_utility(state.subprocess_supervisor, {Clock, []})

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
        %{context: &CallbackContext.from_state/1},
        [],
        %{state | internal_state: options}
      )

    state
  end

  @spec handle_setup(State.t()) :: State.t()
  def handle_setup(state) do
    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_setup,
        ActionHandler,
        %{context: &CallbackContext.from_state/1},
        [],
        state
      )

    with %{setup_incomplete_returned?: false} <- state do
      Membrane.Core.LifecycleController.complete_setup(state)
    end
  end

  @spec handle_playing(State.t()) :: State.t()
  def handle_playing(state) do
    Membrane.Logger.debug("Got play request")

    state =
      %State{state | playback: :playing}
      |> EffectiveFlowController.resolve_effective_flow_control()

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_playing,
        ActionHandler,
        %{context: &CallbackContext.from_state/1},
        [],
        state
      )

    PlaybackQueue.eval(state)
  end

  @spec handle_terminate_request(State.t()) :: State.t()
  def handle_terminate_request(state) do
    Membrane.Logger.debug("Received terminate request")

    state =
      state.pads_data
      |> Map.values()
      |> Enum.filter(&(&1.direction == :input))
      |> Enum.reduce(state, fn %{ref: pad_ref}, state_acc ->
        Element.PadController.generate_eos_if_needed(pad_ref, state_acc)
      end)

    state = %{state | terminating?: true}

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_terminate_request,
        ActionHandler,
        %{context: &CallbackContext.from_state/1},
        [],
        state
      )

    %{state | playback: :stopped}
  end

  @doc """
  Handles custom messages incoming to element.
  """
  @spec handle_info(message :: any, State.t()) :: State.t()
  def handle_info(message, state) do
    CallbackHandler.exec_and_handle_callback(
      :handle_info,
      ActionHandler,
      %{context: &CallbackContext.from_state/1},
      [message],
      state
    )
  end
end
