defmodule Membrane.Core.Element.LifecycleController do
  @moduledoc false
  # Module handling element initialization, termination, playback state changes
  # and similar stuff.

  use Membrane.Core.PlaybackHandler
  use Membrane.Core.Element.Log
  use Bunch
  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Core.Playback
  require Membrane.Element.CallbackContext.{Other, PlaybackChange}
  alias Membrane.{Clock, Element, Sync}
  alias Membrane.Core.{CallbackHandler, Message}
  alias Membrane.Core.Element.{ActionHandler, PlaybackBuffer, State}
  alias Membrane.Element.CallbackContext
  alias Membrane.Core.Child.PadController

  @doc """
  Performs initialization tasks and executes `handle_init` callback.
  """
  @spec handle_init(Element.options_t(), State.t()) :: State.stateful_try_t()
  def handle_init(options, %State{module: module} = state) do
    debug("Initializing element: #{inspect(module)}, options: #{inspect(options)}", state)

    :ok = Sync.register(state.synchronization.stream_sync)

    state =
      if Bunch.Module.check_behaviour(module, :membrane_clock?) do
        {:ok, clock} = Clock.start_link()
        put_in(state.synchronization.clock, clock)
      else
        state
      end

    with {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_init,
             ActionHandler,
             %{state: false},
             [options],
             state
           ) do
      debug("Element initialized: #{inspect(module)}", state)
      {:ok, state}
    else
      {{:error, reason}, state} ->
        warn_error("Failed to initialize element", reason, state)
    end
  end

  @doc """
  Performs shutdown checks and executes `handle_shutdown` callback.
  """
  @spec handle_shutdown(reason :: any, State.t()) :: {:ok, State.t()}
  def handle_shutdown(reason, state) do
    playback_state = state |> Playbackable.get_playback() |> Map.get(:state)

    if playback_state == :terminating do
      debug("Terminating element, reason: #{inspect(reason)}", state)
    else
      warn(
        "Terminating element possibly not prepared for termination as it was in state #{
          inspect(playback_state)
        }. Reason: #{inspect(reason)}",
        state
      )
    end

    %State{module: module, internal_state: internal_state} = state
    :ok = module.handle_shutdown(reason, internal_state)
    {:ok, state}
  end

  @spec handle_pipeline_down(reason :: any, State.t()) :: {:ok, State.t()}
  def handle_pipeline_down(reason, state) do
    if reason != :normal do
      warn_error(
        "Shutting down because of pipeline failure",
        {:pipeline_failure, reason: reason},
        state
      )
    end

    handle_shutdown(reason, state)
  end

  @doc """
  Handles custom messages incoming to element.
  """
  @spec handle_other(message :: any, State.t()) :: State.stateful_try_t()
  def handle_other(message, state) do
    context = &CallbackContext.Other.from_state/1

    CallbackHandler.exec_and_handle_callback(
      :handle_other,
      ActionHandler,
      %{context: context},
      [message],
      state
    )
    |> or_warn_error("Error while handling message")
  end

  @impl PlaybackHandler
  def handle_playback_state(old_playback_state, new_playback_state, state) do
    context = &CallbackContext.PlaybackChange.from_state/1
    callback = PlaybackHandler.state_change_callback(old_playback_state, new_playback_state)

    state =
      if old_playback_state == :playing and new_playback_state == :prepared do
        state.pads.data
        |> Map.values()
        |> Enum.filter(&(&1.direction == :input))
        |> Enum.map(& &1.ref)
        |> Enum.reduce(state, fn pad, state_acc ->
          {:ok, state} = PadController.generate_eos_if_needed(pad, state_acc)
          state
        end)
      else
        state
      end

    CallbackHandler.exec_and_handle_callback(
      callback,
      ActionHandler,
      %{context: context},
      [],
      state
    )
  end

  @impl PlaybackHandler
  def handle_playback_state_changed(_old, new, state) do
    if new == :terminating, do: unlink(state.pads.data)

    PlaybackBuffer.eval(state)
  end

  @doc """
  Locks on stopped state and unlinks all element's pads.
  """
  @spec terminate(State.t()) :: State.stateful_try_t()
  def terminate(state) do
    with {:ok, state} <-
           PlaybackHandler.change_and_lock_playback_state(:terminating, __MODULE__, state) do
      {{:ok, {:stop, :normal, state}}, state}
    end
  end

  defp unlink(pads_data) do
    pads_data
    |> Map.values()
    |> Enum.each(&Message.send(&1.pid, :handle_unlink, &1.other_ref))
  end
end
