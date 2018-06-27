defmodule Membrane.Core.Playback do
  @moduledoc """
  Behaviour for modules that have playback state, i.e. elements and pipelines

  There are three playback states: :stopped, :prepared and :playing.
  Playback state always changes only one step at once in this order, and can
  be handled by `handle_prepare/2`, `handle_play/1` and `handle_stop/1` callbacks
  """
  use Membrane.Helper

  defstruct state: :stopped,
            pending_state: nil,
            target_state: :stopped,
            target_locked?: false,
            async_state_change: false

  @type t :: %__MODULE__{
          state: state_t,
          pending_state: state_t | nil,
          target_state: state_t,
          target_locked?: boolean,
          async_state_change: boolean
        }

  @type state_t :: :stopped | :prepared | :playing

  @callback change_playback_state(pid, atom) :: :ok | {:error, any}
  @callback handle_playback_state(atom, atom, any) :: {:ok, any} | {:error, any}
  @callback handle_playback_state_changed(atom, atom, any) :: {:ok, any} | {:error, any}
  @callback playback_warn_error(String.t(), any, any) :: {:error, any}
  @optional_callbacks handle_playback_state_changed: 3, playback_warn_error: 3

  @states [:stopped, :prepared, :playing]
  @states_positions @states |> Enum.with_index() |> Map.new()

  def states, do: @states

  def next_state(current, target) do
    with {:ok, curr_pos} <-
           @states_positions[current]
           |> Helper.wrap_nil(:invalid_current_playback_state),
         {:ok, target_pos} <-
           @states_positions[target]
           |> Helper.wrap_nil(:invalid_target_playback_state) do
      next_state =
        cond do
          curr_pos < target_pos -> @states |> Enum.at(curr_pos + 1)
          curr_pos > target_pos -> @states |> Enum.at(curr_pos - 1)
        end

      {:ok, next_state}
    end
  end

  defmacro __using__(_) do
    use Membrane.Helper

    quote location: :keep do
      alias Membrane.Core.Playbackable
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      def handle_playback_state_changed(_old, _new, playbackable), do: {:ok, playbackable}

      def playback_warn_error(message, reason, _state) do
        use Membrane.Log
        warn_error(message, reason)
      end

      @doc false
      def play(pid), do: change_playback_state(pid, :playing)

      @doc false
      def prepare(pid), do: change_playback_state(pid, :prepared)

      @doc false
      def stop(pid), do: change_playback_state(pid, :stopped)

      @doc false
      def resolve_playback_change(new_playback_state, playbackable) do
        playbackable =
          playbackable
          |> Playbackable.update_playback(&%{&1 | target_state: new_playback_state})

        playback = playbackable |> Playbackable.get_playback()

        if playback.pending_state == nil and playback.state != new_playback_state do
          do_resolve_playback_change(playback, playbackable)
        else
          {:ok, playbackable}
        end
      end

      defp do_resolve_playback_change(playback, playbackable) do
        with {:ok, next_playback_state} <-
               Playback.next_state(playback.state, playback.target_state),
             {:ok, playbackable} <-
               handle_playback_state(playback.state, next_playback_state, playbackable) do
          {playback, playbackable} =
            playbackable
            |> Playbackable.get_and_update_playback(
              &%Playback{&1 | pending_state: next_playback_state}
            )

          if playback.async_state_change do
            {:ok, playbackable}
          else
            continue_playback_change(playbackable)
          end
        else
          {{:error, reason}, playbackable} ->
            playback_warn_error(
              """
              Unable to change playback state
              from #{inspect(playback.state)} to #{inspect(playback.target_state)}
              """,
              reason,
              playbackable
            )

          {:error, reason} ->
            playback_warn_error(
              """
              Unable to change playback state
              from #{inspect(playback.state)} to #{inspect(playback.target_state)}}
              """,
              reason,
              playbackable
            )
        end
      end

      @doc false
      def lock_playback_state(new_playback_state \\ nil, playbackable) do
        playback = playbackable |> Playbackable.get_playback()

        with :ok <-
               (if playback.target_locked? do
                  {:error, :playback_already_locked}
                else
                  :ok
                end) do
          playbackable
          |> Playbackable.update_playback(
            &%Playback{&1 | target_state: new_playback_state || &1.state, target_locked?: true}
          )

          resolve_playback_change(new_playback_state, playbackable)
        end
      end

      @doc false
      def unlock_playback_state(playbackable) do
        playback = playbackable |> Playbackable.get_playback()

        with :ok <-
               (if playback.target_locked? do
                  :ok
                else
                  {:error, :playback_already_unlocked}
                end) do
          playbackable =
            playbackable
            |> Playbackable.update_playback(&%Playback{&1 | target_locked?: true})

          {:ok, playbackable}
        end
      end

      @doc false
      def suspend_playback_change(playbackable) do
        {:ok, playbackable |> Playbackable.update_playback(&%{&1 | async_state_change: true})}
      end

      @doc false
      def continue_playback_change(playbackable) do
        {old_playback, playbackable} =
          playbackable
          |> Playbackable.get_and_update_playback(
            &%Playback{
              &1
              | async_state_change: false,
                state: &1.pending_state,
                pending_state: nil
            }
          )

        with {:ok, playbackable} <-
               handle_playback_state_changed(
                 old_playback.state,
                 old_playback.pending_state,
                 playbackable
               ) do
          playback = playbackable |> Playbackable.get_playback()
          controlling_pid = playbackable |> Playbackable.get_controlling_pid()

          if controlling_pid do
            send(controlling_pid, {:membrane_playback_state_changed, self(), playback.state})
          end

          resolve_playback_change(playback.target_state, playbackable)
        end
      end

      defoverridable handle_playback_state_changed: 3,
                     playback_warn_error: 3,
                     play: 1,
                     prepare: 1,
                     stop: 1,
                     suspend_playback_change: 1,
                     continue_playback_change: 1,
                     resolve_playback_change: 2
    end
  end
end
