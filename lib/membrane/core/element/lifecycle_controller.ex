defmodule Membrane.Core.Element.LifecycleController do
  alias Membrane.Core
  alias Core.CallbackHandler
  alias Core.Element.{ActionHandler, PadController, PadModel, State}
  require PadModel
  use Core.Element.Log

  def handle_init(options, %State{module: module} = state) do
    debug("Initializing element: #{inspect(module)}, options: #{inspect(options)}", state)

    with {:ok, state} <- PadController.init_pads(state),
         {:ok, state} <- do_handle_init(module, options, state) do
      debug("Element initialized: #{inspect(module)}", state)
      {:ok, state}
    else
      {{:error, reason}, _state} ->
        warn_error("Failed to initialize element", reason, state)
    end
  end

  defp do_handle_init(module, options, state) do
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

  def handle_pipeline_down(reason, state) do
    if reason != :normal do
      warn_error(
        "Failing because of pipeline failure",
        {:pipeline_failure, reason: reason},
        state
      )
    end

    {:ok, state}
  end

  def handle_message(message, state) do
    CallbackHandler.exec_and_handle_callback(:handle_other, ActionHandler, [message], state)
    |> or_warn_error("Error while handling message")
  end

  def handle_message_bus(message_bus, state), do: {:ok, %{state | message_bus: message_bus}}

  def handle_controlling_pid(pid, state), do: {:ok, %{state | controlling_pid: pid}}

  def handle_demand_in(demand_in, pad_name, state) do
    PadModel.assert_data!(pad_name, %{direction: :source}, state)

    PadModel.set_data(
      pad_name,
      [:options, :other_demand_in],
      demand_in,
      state
    )
  end

  def handle_playback_state(:prepared, :playing, state),
    do: CallbackHandler.exec_and_handle_callback(:handle_play, ActionHandler, [], state)

  def handle_playback_state(:prepared, :stopped, state),
    do: CallbackHandler.exec_and_handle_callback(:handle_stop, ActionHandler, [], state)

  def handle_playback_state(ps, :prepared, state) when ps in [:stopped, :playing],
    do: CallbackHandler.exec_and_handle_callback(:handle_prepare, ActionHandler, [ps], state)
end
