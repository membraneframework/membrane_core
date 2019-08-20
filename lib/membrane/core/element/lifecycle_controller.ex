defmodule Membrane.Core.Element.LifecycleController do
  @moduledoc false
  # Module handling element initialization, termination, playback state changes
  # and similar stuff.

  use Membrane.Core.PlaybackHandler
  use Membrane.Core.Element.Log
  use Bunch
  require Membrane.Core.Element.PadModel
  require Membrane.Core.Message
  require Membrane.Core.Playback
  require Membrane.Element.CallbackContext.{Other, PlaybackChange}
  alias Membrane.{Clock, Sync}
  alias Membrane.Core.{CallbackHandler, Message, Playback}
  alias Membrane.Core.Element.{ActionHandler, PadModel, PlaybackBuffer, State}
  alias Membrane.Element.{CallbackContext, Pad}

  @doc """
  Performs initialization tasks and executes `handle_init` callback.
  """
  @spec handle_init(Element.options_t(), State.t()) :: State.stateful_try_t()
  def handle_init(options, %State{module: module} = state) do
    debug("Initializing element: #{inspect(module)}, options: #{inspect(options)}", state)

    :ok = Sync.register(state.stream_sync)

    state =
      if Bunch.Module.check_behaviour(module, :membrane_clock?) do
        %State{state | clock: Clock.start_link!()}
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
    if state.terminating == :ready do
      debug("Terminating element, reason: #{inspect(reason)}", state)
    else
      warn(
        "Terminating element possibly not prepared for termination. Reason: #{inspect(reason)}",
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

  @spec handle_watcher(pid, State.t()) :: {:ok, State.t()}
  def handle_watcher(watcher, state) do
    {{:ok, state |> Map.take([:clock])}, %State{state | watcher: watcher}}
  end

  @spec handle_controlling_pid(pid, State.t()) :: {:ok, State.t()}
  def handle_controlling_pid(pid, state), do: {:ok, %{state | controlling_pid: pid}}

  @doc """
  Stores demand unit of subsequent element pad.
  """
  @spec handle_demand_unit(demand_unit :: atom, Pad.ref_t(), State.t()) :: {:ok, State.t()}
  def handle_demand_unit(demand_unit, pad_ref, state) do
    PadModel.assert_data!(state, pad_ref, %{direction: :output})

    state
    |> PadModel.set_data!(pad_ref, [:other_demand_unit], demand_unit)
    ~> {:ok, &1}
  end

  @impl PlaybackHandler
  def handle_playback_state(old_playback_state, new_playback_state, state) do
    context = &CallbackContext.PlaybackChange.from_state/1
    callback = PlaybackHandler.state_change_callback(old_playback_state, new_playback_state)

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
    shutdown_res =
      if new == :stopped and state.terminating == true do
        prepare_shutdown(state)
      else
        {:ok, state}
      end

    with {:ok, state} <- shutdown_res do
      PlaybackBuffer.eval(state)
    end
  end

  @doc """
  Locks on stopped state and unlinks all element's pads.
  """
  @spec prepare_shutdown(State.t()) :: State.stateful_try_t()
  def prepare_shutdown(state) do
    if state.playback.state == :stopped and state.playback |> Playback.stable?() do
      {_result, state} = PlaybackHandler.lock_target_state(state)
      unlink(state.pads.data)
      Message.send(state.watcher, :shutdown_ready, state.name)
      {:ok, %State{state | terminating: :ready}}
    else
      state = %State{state | terminating: true}
      PlaybackHandler.change_and_lock_playback_state(:stopped, __MODULE__, state)
    end
  end

  defp unlink(pads_data) do
    pads_data
    |> Map.values()
    |> Enum.each(&Message.send(&1.pid, :handle_unlink, &1.other_ref))
  end
end
