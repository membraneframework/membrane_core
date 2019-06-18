defmodule Membrane.Core.Element.LifecycleController do
  @moduledoc false
  # Module handling element initialization, termination, playback state changes
  # and similar stuff.

  alias Membrane.{Core, Element, Sync}
  alias Core.{CallbackHandler, Message}
  alias Core.Element.{ActionHandler, PadModel, PlaybackBuffer, State}
  alias Element.{CallbackContext, Pad}
  require CallbackContext.{Other, PlaybackChange}
  require Message
  require PadModel
  use Core.PlaybackHandler
  use Core.Element.Log
  use Bunch

  @doc """
  Performs initialization tasks and executes `handle_init` callback.
  """
  @spec handle_init(Element.options_t(), State.t()) :: State.stateful_try_t()
  def handle_init(options, %State{module: module} = state) do
    debug("Initializing element: #{inspect(module)}, options: #{inspect(options)}", state)

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
  def handle_shutdown(
        reason,
        %State{module: module, internal_state: internal_state, playback: playback} = state
      ) do
    if playback.state == :stopped && !playback.pending_state do
      debug("Terminating element, reason: #{inspect(reason)}", state)
    else
      warn_error(
        """
        Terminating: Attempt to terminate element when it is not stopped
        """,
        reason,
        state
      )
    end

    :ok = module.handle_shutdown(internal_state)
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
  def handle_watcher(watcher, state), do: {:ok, %{state | watcher: watcher}}

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
  def handle_playback_state_changed(old, new, state) do
    :ok =
      case {old, new} do
        {:prepared, :playing} -> Sync.ready(state.stream_sync)
        {:playing, :prepared} -> Sync.unready(state.stream_sync)
        _ -> :ok
      end

    PlaybackBuffer.eval(state)
  end

  @doc """
  Unlinks all element's pads.
  """
  @spec unlink(State.t()) :: State.stateful_try_t()
  def unlink(%State{playback: %{state: :stopped}} = state) do
    with :ok <-
           state.pads.data
           |> Bunch.Enum.try_each(fn {_name, %{pid: pid, other_ref: other_ref}} ->
             Message.call(pid, :handle_unlink, other_ref)
           end) do
      {:ok, state}
    end
  end

  def unlink(state) do
    warn_error(
      """
      Tried to unlink Element that is not stopped
      """,
      {:unlink, :cannot_unlink_non_stopped_element},
      state
    )
  end
end
