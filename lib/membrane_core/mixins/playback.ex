defmodule Membrane.Mixins.Playback do
  use Membrane.Helper

  @type state_t :: :stopped | :prepared | :playing

  @callback change_playback_state(pid, atom) :: :ok | {:error, any}
  @callback handle_playback_state(atom, atom, any) :: {:ok, any} | {:error, any}
  @callback handle_playback_state_changed(atom, atom, any) :: {:ok, any} | {:error, any}
  @callback playback_warn_error(String.t, any, any) :: {:error, any}
  @optional_callbacks handle_playback_state_changed: 3, playback_warn_error: 3

  @states %{0 => :stopped, 1 => :prepared, 2 => :playing}
  @states_pos @states |> Enum.into(%{}, fn {k, v} -> {v, k} end)

  def states, do: @states
  def states_pos, do: @states_pos

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Mixins.Playback


      def handle_playback_state_changed(_old, _new, state), do: {:ok, state}

      def playback_warn_error(message, reason, _state) do
        use Membrane.Mixins.Log
        warn_error message, reason
      end

      def play(pid), do: change_playback_state(pid, :playing)
      def prepare(pid), do: change_playback_state(pid, :prepared)
      def stop(pid), do: change_playback_state(pid, :stopped)


      def resolve_playback_change(new_state, %{playback_state: new_state} = state), do:
        {:ok, state}

      def resolve_playback_change(new_state, %{pending_playback_state: pending_state} = state)
      when pending_state != nil, do:
        {:ok, %{state | target_playback_state: new_state}}

      def resolve_playback_change(new_state, state) do
        use Membrane.Helper
        alias Membrane.Mixins.Playback

        state = state |> Map.put(:target_playback_state, new_state)
        old_state = state |> Map.get(:playback_state)

        with \
          {:ok, old_pos} <- Playback.states_pos[old_state] |> Helper.wrap_nil(:invalid_old_playback),
          {:ok, new_pos} <- Playback.states_pos[new_state] |> Helper.wrap_nil(:invalid_new_playback),
          {:ok, state} <- old_pos..new_pos
            |> Enum.chunk(2, 1)
            |> Enum.reduce_while({:ok, state}, fn [i, j], {:ok, st} ->
                with \
                  {:ok, st} <- handle_playback_state(Playback.states[i], Playback.states[j], st),
                  {:sync, st} <- get_state_change_mode(st),
                  st = st |> Map.put(:playback_state, Playback.states[j]),
                  send(st.controlling_pid, {:membrane_playback_state_changed, self(), Playback.states[j]})
                    |> provided(that: st.controlling_pid),
                  {:ok, st} <- handle_playback_state_changed(Playback.states[i], Playback.states[j], st)
                do
                  {:cont, {:ok, st}}
                else
                  {:async, st} ->
                    st =  st |> Map.merge(%{pending_playback_state: Playback.states[j]})
                    {:halt, {:ok, st}}
                  err ->
                    {:halt, err}
                end
              end)
        do
          {:ok, state}
        else
          :invalid_old_playback -> playback_warn_error """
            Cannot change playback state, because current_playback_state callback
            returned invalid playback state: #{inspect old_state}
            """, :invalid_old_playback, state
          :invalid_new_playback -> playback_warn_error """
            Cannot change playback state, because passed
            playback state: #{inspect new_state} is invalid
            """, :invalid_new_playback, state
          {{:error, reason}, st} -> playback_warn_error """
            Unable to change playback state from #{inspect old_state} to #{inspect new_state}
            """, reason, state
            {{:error, reason}, st}
          {:error, reason} -> playback_warn_error """
            Unable to change playback state from #{inspect old_state} to #{inspect new_state}
            """, reason, state
        end
      end

      defp get_state_change_mode(%{async_state_change: true} = state), do: {:async, state}
      defp get_state_change_mode(state), do: {:sync, state}

      def continue_playback_change(state) do
        previous_state = state.playback_state

        state = state
          |> Map.put(:async_state_change, false)
          |> Map.put(:playback_state, state.pending_playback_state)
          |> Map.put(:pending_playback_state, nil)

        {:ok, state} = handle_playback_state_changed(previous_state, state.playback_state, state)

        if Map.get(state, :controlling_pid, nil) do
          send state.controlling_pid, {:membrane_playback_state_changed, self(), state.playback_state}
        end

        resolve_playback_change(state.target_playback_state, state)
      end

      defoverridable [
        handle_playback_state_changed: 3,
        playback_warn_error: 3,
        play: 1,
        prepare: 1,
        stop: 1,
        continue_playback_change: 1,
        resolve_playback_change: 2,
      ]

    end
  end

end
