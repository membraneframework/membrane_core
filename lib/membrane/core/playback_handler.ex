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
  def change_playback_state(new_playback_state, handler, playbackable) do
    {playback, playbackable} =
      playbackable
      |> Playbackable.get_and_update_playback(fn
        %Playback{target_locked?: true} = p -> {p, p}
        %Playback{} = p -> %Playback{p | target_state: new_playback_state} ~> {&1, &1}
      end)

    playbackable = lock_if_terminating(playbackable, new_playback_state)

    if playback.pending_state == nil and playback.state != playback.target_state do
      do_change_playback_state(playback, handler, playbackable)
    else
      {:ok, playbackable}
    end
  end

  defp lock_if_terminating(playbackable, target_state)

  defp lock_if_terminating(playbackable, :terminating) do
    Playbackable.update_playback(playbackable, &%{&1 | target_locked?: true})
  end

  defp lock_if_terminating(playbackable, _), do: playbackable

  defp do_change_playback_state(playback, handler, playbackable) do
    with {{:ok, next_playback_state}, playbackable} <-
           {next_state(playback.state, playback.target_state), playbackable},
         {:ok, playbackable} <-
           handler.handle_playback_state(playback.state, next_playback_state, playbackable) do
      {async_state_change, playbackable} =
        playbackable
        |> Playbackable.get_and_update_playback(
          &{&1.async_state_change, %Playback{&1 | pending_state: next_playback_state}}
        )

      if async_state_change do
        {:ok, playbackable}
      else
        continue_playback_change(handler, playbackable)
      end
    end
  end

  @spec suspend_playback_change(pb) :: {:ok, pb} when pb: Playbackable.t()
  def suspend_playback_change(playbackable) do
    {:ok, playbackable |> Playbackable.update_playback(&%{&1 | async_state_change: true})}
  end

  @spec continue_playback_change(module, Playbackable.t()) :: handler_return_t()
  def continue_playback_change(handler, playbackable) do
    {old_playback, playbackable} =
      playbackable
      |> Playbackable.get_and_update_playback(fn p ->
        {p,
         %Playback{
           p
           | async_state_change: false,
             state: p.pending_state,
             pending_state: nil
         }}
      end)

    handler_res =
      handler.handle_playback_state_changed(
        old_playback.state,
        old_playback.pending_state,
        playbackable
      )

    case handler_res do
      {:stop, _reason, playbackable} = stop_tuple ->
        maybe_notify_controller(handler, playbackable)
        stop_tuple

      {:ok, playbackable} ->
        maybe_notify_controller(handler, playbackable)
        playback = Playbackable.get_playback(playbackable)

        change_playback_state(playback.target_state, handler, playbackable)

      res ->
        warn(
          "PlaybackHandler got unknown result from callback handle_playback_state_changed: #{
            inspect(handler_res)
          }. Not proceeding with palyback state change."
        )

        res
    end
  end

  defp maybe_notify_controller(handler, playbackable) do
    playback = playbackable |> Playbackable.get_playback()

    if controlling_pid = playbackable |> Playbackable.get_controlling_pid() do
      handler.notify_controller(:playback_changed, playback.state, controlling_pid)
    end
  end

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
