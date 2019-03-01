defmodule Membrane.Core.PlaybackHandler do
  @moduledoc false
  # Behaviour for modules that have playback state, i.e. elements and pipelines
  #
  # There are three playback states: :stopped, :prepared and :playing.
  # Playback state always changes only one step at once in this order, and can
  # be handled by `handle_stopped_to_prepared`, `handle_playing_to_prepared`,
  # `handle_prepared_to_playing` and `handle_prepared_to_stopped` callbacks.

  alias Membrane.Core.{Playback, Playbackable}
  use Bunch

  @type handler_return_t :: {:ok | {:error, any()}, Playbackable.t()}

  @doc """
  Callback invoked when playback state is going to be changed.
  """
  @callback handle_playback_state(Playback.state_t(), Playback.state_t(), Playbackable.t()) ::
              handler_return_t

  @doc """
  Callback invoked when playback state has changed.
  """
  @callback handle_playback_state_changed(
              Playback.state_t(),
              Playback.state_t(),
              Playbackable.t()
            ) :: handler_return_t

  @doc """
  Callback that is to notify controller that playback state has changed.
  """
  @callback notify_controller(:playback_changed, Playback.state_t(), pid) :: :ok

  @states [:stopped, :prepared, :playing]
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
  @spec state_change_callback(prev_state :: Playback.state_t(), next_state :: Playback.state_t()) ::
          atom()
  def state_change_callback(:stopped, :prepared), do: :handle_stopped_to_prepared
  def state_change_callback(:playing, :prepared), do: :handle_playing_to_prepared
  def state_change_callback(:prepared, :playing), do: :handle_prepared_to_playing
  def state_change_callback(:prepared, :stopped), do: :handle_prepared_to_stopped

  def change_playback_state(new_playback_state, handler, playbackable) do
    {playback, playbackable} =
      playbackable
      |> Playbackable.get_and_update_playback(fn
        %Playback{target_locked?: true} = p -> {p, p}
        %Playback{} = p -> %Playback{p | target_state: new_playback_state} ~> {&1, &1}
      end)

    if playback.pending_state == nil and playback.state != new_playback_state do
      do_change_playback_state(playback, handler, playbackable)
    else
      {:ok, playbackable}
    end
  end

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

  def change_and_lock_playback_state(new_playback_state, handler, playbackable) do
    with {:ok, playbackable} <- lock_target_state(playbackable) do
      playbackable =
        playbackable
        |> Playbackable.update_playback(&%Playback{&1 | target_state: new_playback_state})

      change_playback_state(new_playback_state, handler, playbackable)
    end
  end

  def lock_target_state(playbackable) do
    if Playbackable.get_playback(playbackable).target_locked? do
      {{:error, :playback_already_locked}, playbackable}
    else
      {:ok, switch_target_lock(playbackable)}
    end
  end

  def unlock_target_state(playbackable) do
    if Playbackable.get_playback(playbackable).target_locked? do
      {:ok, switch_target_lock(playbackable)}
    else
      {{:error, :playback_already_unlocked}, playbackable}
    end
  end

  def suspend_playback_change(playbackable) do
    {:ok, playbackable |> Playbackable.update_playback(&%{&1 | async_state_change: true})}
  end

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

    with {:ok, playbackable} <-
           handler.handle_playback_state_changed(
             old_playback.state,
             old_playback.pending_state,
             playbackable
           ) do
      playback = playbackable |> Playbackable.get_playback()

      if controlling_pid = playbackable |> Playbackable.get_controlling_pid() do
        handler.notify_controller(:playback_changed, playback.state, controlling_pid)
      end

      change_playback_state(playback.target_state, handler, playbackable)
    end
  end

  defp switch_target_lock(playbackable) do
    playbackable
    |> Playbackable.update_playback(&%Playback{&1 | target_locked?: not &1.target_locked?})
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
