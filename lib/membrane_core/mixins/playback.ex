defmodule Membrane.Mixins.Playback do
  use Membrane.Helper

  defstruct [
    state: :stopped,
    pending_state: nil,
    target_state: nil,
    async_state_change: false,
  ]

  @type t :: %__MODULE__{
    state: state_t,
    pending_state: state_t | nil,
    target_state: state_t | nil,
    async_state_change: boolean,
  }

  @type state_t :: :stopped | :prepared | :playing

  @callback change_playback_state(pid, atom) :: :ok | {:error, any}
  @callback handle_playback_state(atom, atom, any) :: {:ok, any} | {:error, any}
  @callback handle_playback_state_changed(atom, atom, any) :: {:ok, any} | {:error, any}
  @callback playback_warn_error(String.t, any, any) :: {:error, any}
  @optional_callbacks handle_playback_state_changed: 3, playback_warn_error: 3

  @states [:stopped, :prepared, :playing]

  def states, do: @states
  def next_state(current, target) do
    with \
      {:ok, curr_pos} <- @states |> Enum.find_index(& &1 == current)
        |> Helper.wrap_nil(:invalid_current_playback_state),
      {:ok, target_pos} <-  @states |> Enum.find_index(& &1 == target)
        |> Helper.wrap_nil(:invalid_target_playback_state)
    do
      next_state = cond do
        curr_pos < target_pos -> @states |> Enum.at(curr_pos + 1)
        curr_pos > target_pos -> @states |> Enum.at(curr_pos - 1)
      end
      {:ok, next_state}
    end
  end

  defmacro __using__(_) do
    use Membrane.Helper

    quote location: :keep do
      alias Membrane.Mixins.{Playback, Playbackable}
      @behaviour Playback

      def handle_playback_state_changed(_old, _new, state), do: {:ok, state}

      def playback_warn_error(message, reason, _state) do
        use Membrane.Mixins.Log
        warn_error message, reason
      end

      def play(pid), do: change_playback_state(pid, :playing)
      def prepare(pid), do: change_playback_state(pid, :prepared)
      def stop(pid), do: change_playback_state(pid, :stopped)


      def resolve_playback_change(new_playback_state, state) do
        old_playback = state |> Playbackable.get_playback
        playback = %Playback{old_playback | target_state: new_playback_state}
        state = state |> Playbackable.set_playback(playback)
        if old_playback.pending_state == nil and old_playback.state != new_playback_state do
          do_resolve_playback_change(playback, state)
        else
          {:ok, state}
        end
      end

      defp do_resolve_playback_change(playback, state) do
        with \
          {:ok, next_playback_state} <- Playback.next_state(playback.state, playback.target_state),
          {:ok, state} <- handle_playback_state(playback.state, next_playback_state, state)
        do
          {playback, state} = state
            |> Playbackable.get_and_update_playback(& %Playback{&1 | pending_state: next_playback_state})
          if playback.async_state_change do
            {:ok, state}
          else
            continue_playback_change(state)
          end
        else
          {{:error, reason}, state} -> playback_warn_error """
            Unable to change playback state
            from #{inspect playback.state} to #{inspect playback.target_state}
            """, reason, state
          {:error, reason} -> playback_warn_error """
            Unable to change playback state
            from #{inspect playback.state} to #{inspect playback.target_state}}
            """, reason, state
        end
      end

      def suspend_playback_change(state) do
        {:ok, state |> Playbackable.update_playback(& %{&1 | async_state_change: true})}
      end

      def continue_playback_change(state) do
        {old_playback, state} = state |> Playbackable.get_and_update_playback(
          & %Playback{&1 |
            async_state_change: false,
            state: &1.pending_state,
            pending_state: nil,
          })
        with {:ok, state} <-
          handle_playback_state_changed(old_playback.state, old_playback.pending_state, state)
        do
          playback = state |> Playbackable.get_playback
          controlling_pid = state |> Playbackable.get_controlling_pid
          if controlling_pid do
            send controlling_pid, {:membrane_playback_state_changed, self(), playback.state}
          end
          resolve_playback_change(playback.target_state, state)
        end
      end

      defoverridable [
        handle_playback_state_changed: 3,
        playback_warn_error: 3,
        play: 1,
        prepare: 1,
        stop: 1,
        suspend_playback_change: 1,
        continue_playback_change: 1,
        resolve_playback_change: 2,
      ]

    end
  end

end
