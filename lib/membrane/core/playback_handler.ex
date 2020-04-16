defmodule Membrane.Core.PlaybackHandler do
  @moduledoc false

  # Behaviour for modules that have playback state, i.e. elements and pipelines
  #
  # There are three playback states: :stopped, :prepared and :playing.
  # Playback state always changes only one step at once in this order, and can
  # be handled by `handle_stopped_to_prepared`, `handle_playing_to_prepared`,
  # `handle_prepared_to_playing` and `handle_prepared_to_stopped` callbacks.

  alias Membrane.Core.{Message, Playback, Playbackable}
  alias Membrane.PlaybackState

  require PlaybackState
  require Message

  use Bunch
  use Membrane.Log, tags: :core

  @type handler_return_t ::
          {:ok | {:error, any()}, Playbackable.t()} | {:stop, any(), Playbackable.t()}

  @doc """
  Callback invoked when playback state is going to be changed.
  """
  @callback handle_playback_state(PlaybackState.t(), PlaybackState.t(), Playbackable.t()) ::
              handler_return_t

  @doc """
  Callback invoked when playback state has changed.
  """
  @callback handle_playback_state_changed(
              PlaybackState.t(),
              PlaybackState.t(),
              Playbackable.t()
            ) :: handler_return_t

  @doc """
  Callback that is to notify controller that playback state has changed.
  """
  @callback notify_controller(:playback_changed, PlaybackState.t(), pid) :: :ok

  @states [:terminating, :stopped, :prepared, :playing]
  @states_positions @states |> Enum.with_index() |> Map.new()

  defmacro __using__(_) do
    quote location: :keep do
      alias Membrane.Core.Playbackable
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      @impl unquote(__MODULE__)
      def handle_playback_state(_old, _new, playbackable), do: {:ok, playbackable}

      @impl unquote(__MODULE__)
      def handle_playback_state_changed(_old, _new, playbackable), do: {:ok, playbackable}

      @impl unquote(__MODULE__)
      def notify_controller(:playback_changed, playback_state, controlling_pid) do
        alias Membrane.Core.Message
        require Message
        Message.send(controlling_pid, :playback_state_changed, [self(), playback_state])
        :ok
      end

      defoverridable unquote(__MODULE__)
    end
  end

  @doc """
  Returns callback name for transition between playback states
  """
  @spec state_change_callback(prev_state :: PlaybackState.t(), next_state :: PlaybackState.t()) ::
          :handle_playing_to_prepared
          | :handle_prepared_to_playing
          | :handle_prepared_to_stopped
          | :handle_stopped_to_prepared
          | :handle_stopped_to_terminating
  def state_change_callback(:stopped, :prepared), do: :handle_stopped_to_prepared
  def state_change_callback(:playing, :prepared), do: :handle_playing_to_prepared
  def state_change_callback(:prepared, :playing), do: :handle_prepared_to_playing
  def state_change_callback(:prepared, :stopped), do: :handle_prepared_to_stopped
  def state_change_callback(:stopped, :terminating), do: :handle_stopped_to_terminating

  @spec request_playback_state_change(pid, Membrane.PlaybackState.t()) :: :ok
  def request_playback_state_change(pid, new_state)
      when Membrane.PlaybackState.is_playback_state(new_state) do
    Message.send(pid, :change_playback_state, new_state)
    :ok
  end

  @spec change_playback_state(PlaybackState.t(), module(), Playbackable.t()) :: handler_return_t()
  def change_playback_state(new_playback_state, handler, state) do
    %{playback: playback} = state

    playback =
      case playback do
        %{target_locked: true} -> playback
        _ -> %{playback | target_state: new_playback_state}
      end

    playback = lock_if_terminating(playback, new_playback_state)

    IO.puts("#{inspect(playback.state)} != #{inspect(playback.target_state)}")

    if playback.pending_state == nil and playback.state != playback.target_state do
      do_change_playback_state(handler, %{state | playback: playback})
    else
      {:ok, %{state | playback: playback}}
    end
  end

  defp lock_if_terminating(playback, target_state)
  defp lock_if_terminating(playback, :terminating), do: %{playback | target_locked?: true}
  defp lock_if_terminating(playback, _), do: playback

  defp do_change_playback_state(handler, state) do
    playback = state.playback

    with {:ok, next_playback_state} <-
           next_state(playback.state, playback.target_state),
         {:ok, state} <-
           handler.handle_playback_state(playback.state, next_playback_state, state) do
      playback = %{state.playback | pending_state: next_playback_state}
      state = %{state | playback: playback}

      if state.playback.async_state_change do
        {:ok, state}
      else
        continue_playback_change(handler, state)
      end
    end
  end

  @spec suspend_playback_change(pb) :: {:ok, pb} when pb: Playbackable.t()
  def suspend_playback_change(state) do
    playback = %{state.playback | async_state_change: true}
    {:ok, %{state | playback: playback}}
  end

  @spec continue_playback_change(module, Playbackable.t()) :: handler_return_t()
  def continue_playback_change(handler, state) do
    old_playback = state.playback

    new_playback = %{
      old_playback
      | async_state_change: false,
        state: old_playback.pending_state,
        pending_state: nil
    }

    state = %{state | playback: new_playback}

    handler_res =
      handler.handle_playback_state_changed(
        old_playback.state,
        old_playback.pending_state,
        state
      )

    case handler_res do
      {:stop, _reason, state} = stop_tuple ->
        maybe_notify_controller(handler, state)
        stop_tuple

      {:ok, state} ->
        maybe_notify_controller(handler, state)

        change_playback_state(state.playback.target_state, handler, state)

      res ->
        warn(
          "PlaybackHandler got unknown result from callback handle_playback_state_changed: #{
            inspect(handler_res)
          }. Not proceeding with palyback state change."
        )

        res
    end
  end

  defp maybe_notify_controller(handler, %{controlling_pid: controlling_pid} = state)
       when not is_nil(controlling_pid),
       do:
         handler.notify_controller(:playback_changed, state.playback.state, state.controlling_pid)

  defp maybe_notify_controller(_handler, _state), do: :ok

  defp next_state(current, target) do
    withl curr: curr_pos when curr_pos != nil <- @states_positions[current],
          target: target_pos when target_pos != nil <- @states_positions[target],
          diff: true <- curr_pos != target_pos do
      next_state =
        if curr_pos < target_pos do
          @states |> Enum.at(curr_pos + 1)
        else
          @states |> Enum.at(curr_pos - 1)
        end

      {:ok, next_state}
    else
      curr: _ -> {:error, :invalid_current_playback_state}
      target: _ -> {:error, :invalid_target_playback_state}
      diff: _ -> {:error, :target_and_current_states_equal}
    end
  end
end
