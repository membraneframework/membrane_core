defmodule Membrane.Core.Element.LifecycleController do
  @moduledoc false

  # Module handling element initialization, termination, playback state changes
  # and similar stuff.

  use Bunch
  use Membrane.Core.PlaybackHandler

  alias Membrane.{Clock, Element, Sync}
  alias Membrane.Core.{CallbackHandler, Child, Element, Message}
  alias Membrane.Core.Element.{ActionHandler, PlaybackBuffer, State}
  alias Membrane.Element.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Core.Playback
  require Membrane.Logger

  @safe_shutdown_reasons [
    {:shutdown, :child_crash},
    {:shutdown, :membrane_crash_group_kill},
    {:shutdown, :parent_crash}
  ]

  @doc """
  Performs initialization tasks and executes `handle_init` callback.
  """
  @spec handle_init(Element.options_t(), State.t()) :: State.stateful_try_t()
  def handle_init(options, %State{module: module} = state) do
    Membrane.Logger.debug(
      "Initializing element: #{inspect(module)}, options: #{inspect(options)}"
    )

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
             %{},
             [options],
             state
           ) do
      Membrane.Logger.debug("Element initialized: #{inspect(module)}")
      {:ok, state}
    else
      {{:error, reason}, state} ->
        Membrane.Logger.error("""
        Failed to initialize element
        Reason: #{inspect(reason)}
        State: #{inspect(state, pretty: true)}
        """)

        {{:error, reason}, state}
    end
  end

  @doc """
  Performs shutdown checks and executes `handle_shutdown` callback.
  """
  @spec handle_shutdown(reason :: any, State.t()) :: {:ok, State.t()}
  def handle_shutdown(reason, state) do
    playback_state = state.playback.state

    cond do
      playback_state == :terminating ->
        Membrane.Logger.debug("Terminating element, reason: #{inspect(reason)}")

      reason in @safe_shutdown_reasons ->
        Membrane.Logger.debug("""
        Terminating element possibly not prepared for termination as it was in state #{inspect(playback_state)}.
        Reason: #{inspect(reason)}"
        """)

      true ->
        Membrane.Logger.warn("""
        Terminating element possibly not prepared for termination as it was in state #{inspect(playback_state)}.
        Reason: #{inspect(reason)},
        State: #{inspect(state, pretty: true)}
        """)
    end

    %State{module: module, internal_state: internal_state} = state

    :ok = module.handle_shutdown(reason, internal_state)
    {:ok, state}
  end

  @spec handle_pipeline_down(reason :: any, State.t()) :: {:ok, State.t()}
  def handle_pipeline_down(reason, state) do
    if reason != :normal do
      Membrane.Logger.debug("""
      Shutting down because of pipeline failure
      Reason: #{inspect(reason)}
      """)
    end

    handle_shutdown(reason, state)
  end

  @doc """
  Handles custom messages incoming to element.
  """
  @spec handle_other(message :: any, State.t()) :: State.stateful_try_t()
  def handle_other(message, state) do
    require CallbackContext.Other
    context = &CallbackContext.Other.from_state/1

    CallbackHandler.exec_and_handle_callback(
      :handle_other,
      ActionHandler,
      %{context: context},
      [message],
      state
    )
  end

  @impl PlaybackHandler
  def handle_playback_state(old_playback_state, new_playback_state, state) do
    require CallbackContext.PlaybackChange
    context = &CallbackContext.PlaybackChange.from_state/1
    callback = PlaybackHandler.state_change_callback(old_playback_state, new_playback_state)

    state =
      case {old_playback_state, new_playback_state} do
        {:stopped, :prepared} ->
          Child.PadController.assert_all_static_pads_linked!(state)
          state

        {:playing, :prepared} ->
          state.pads_data
          |> Map.values()
          |> Enum.filter(&(&1.direction == :input))
          |> Enum.reduce(state, fn %{ref: pad_ref}, state_acc ->
            {:ok, state} = Element.PadController.generate_eos_if_needed(pad_ref, state_acc)
            state
          end)

        _other ->
          state
      end

    if callback do
      CallbackHandler.exec_and_handle_callback(
        callback,
        ActionHandler,
        %{context: context},
        [],
        state
      )
    else
      {:ok, state}
    end
  end

  @impl PlaybackHandler
  def handle_playback_state_changed(old, new, state) do
    Membrane.Logger.debug_verbose("Playback state changed from #{old} to #{new}")

    with {:ok, state} <- PlaybackBuffer.eval(state) do
      if new == :terminating,
        do: {:stop, :normal, state},
        else: {:ok, state}
    end
  end

  @spec handle_parent_notification(Membrane.ParentNotification.t(), State.t()) ::
          State.stateful_try_t()
  def handle_parent_notification(notification, state) do
    CallbackHandler.exec_and_handle_callback(
      :handle_parent_notification,
      ActionHandler,
      %{},
      notification,
      state
    )
  end
end
