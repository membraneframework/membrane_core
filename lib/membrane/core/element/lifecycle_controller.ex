defmodule Membrane.Core.Element.LifecycleController do
  @moduledoc false
  # Module handling element initialization, termination, playback state changes
  # and similar stuff.

  alias Membrane.{Core, Element}
  alias Core.CallbackHandler
  alias Core.Element.{ActionHandler, PadSpecHandler, PadModel, PlaybackBuffer, State}
  alias Element.{CallbackContext, Pad}
  require CallbackContext.{Other, Play, Prepare, Stop}
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

    with {:ok, state} <- PadSpecHandler.init_pads(state),
         {:ok, state} <- exec_init_handler(module, options, state) do
      debug("Element initialized: #{inspect(module)}", state)
      {:ok, state}
    else
      {{:error, reason}, state} ->
        warn_error("Failed to initialize element", reason, state)
    end
  end

  @spec exec_init_handler(module, Element.options_t(), State.t()) :: State.stateful_try_t()
  defp exec_init_handler(module, options, state) do
    with {:ok, internal_state} <- module.handle_init(options) do
      {:ok, %State{state | internal_state: internal_state}}
    else
      {:error, reason} ->
        warn_error(
          """
          Module #{inspect(module)} handle_init callback returned an error
          """,
          {:handle_init, module, reason},
          state
        )

      other ->
        warn_error(
          """
          Module #{inspect(module)} handle_init callback returned invalid result:
          #{inspect(other)} instead of {:ok, state} or {:error, reason}
          """,
          {:invalid_callback_result, :handle_init, other},
          state
        )
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
    case playback.state do
      :stopped ->
        debug("Terminating element, reason: #{inspect(reason)}", state)

      _ ->
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
    warn_error(
      "Shutting down because of pipeline failure",
      {:pipeline_failure, reason: reason},
      state
    )

    handle_shutdown(reason, state)
  end

  @doc """
  Handles message incoming from pipeline.
  """
  @spec handle_message(message :: any, State.t()) :: State.stateful_try_t()
  def handle_message(message, state) do
    ctx = CallbackContext.Other.from_state(state)

    CallbackHandler.exec_and_handle_callback(:handle_other, ActionHandler, [message, ctx], state)
    |> or_warn_error("Error while handling message")
  end

  @spec handle_message_bus(pid, State.t()) :: {:ok, State.t()}
  def handle_message_bus(message_bus, state), do: {:ok, %{state | message_bus: message_bus}}

  @spec handle_controlling_pid(pid, State.t()) :: {:ok, State.t()}
  def handle_controlling_pid(pid, state), do: {:ok, %{state | controlling_pid: pid}}

  @doc """
  Stores demand unit of subsequent element pad.
  """
  @spec handle_demand_in(demand_in :: atom, Pad.name_t(), State.t()) :: {:ok, State.t()}
  def handle_demand_in(demand_in, pad_name, state) do
    PadModel.assert_data!(pad_name, %{direction: :source}, state)

    state =
      PadModel.set_data!(
        pad_name,
        [:options, :other_demand_in],
        demand_in,
        state
      )

    {:ok, state}
  end

  @impl PlaybackHandler
  def handle_playback_state(:prepared, :playing, state) do
    ctx = CallbackContext.Play.from_state(state)
    CallbackHandler.exec_and_handle_callback(:handle_play, ActionHandler, [ctx], state)
  end

  @impl PlaybackHandler
  def handle_playback_state(:prepared, :stopped, state) do
    ctx = CallbackContext.Stop.from_state(state)
    CallbackHandler.exec_and_handle_callback(:handle_stop, ActionHandler, [ctx], state)
  end

  @impl PlaybackHandler
  def handle_playback_state(ps, :prepared, state) when ps in [:stopped, :playing] do
    ctx = CallbackContext.Prepare.from_state(state)
    CallbackHandler.exec_and_handle_callback(:handle_prepare, ActionHandler, [ps, ctx], state)
  end

  @impl PlaybackHandler
  def handle_playback_state_changed(_old, _new, state) do
    PlaybackBuffer.eval(state)
  end

  @doc """
  Unlinks all element's pads.
  """
  @spec unlink(State.t()) :: State.stateful_try_t()
  def unlink(%State{playback: %{state: :stopped}} = state) do
    with :ok <-
           state.pads.data
           |> Bunch.Enum.each_with(fn {_name, %{pid: pid, other_name: other_name}} ->
             GenServer.call(pid, {:membrane_handle_unlink, other_name})
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
