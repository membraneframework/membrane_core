defmodule Membrane.Mixins.Playback do
  use Membrane.Helper

  @type state_t :: atom

  @callback current_playback_state(any) :: atom
  @callback handle_playback_state(atom, atom, any) :: {:ok, any} | {:error, any}

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Mixins.Playback

      def change_playback_state(pid, new_state) do
        GenServer.call pid, {:membrane_change_playback_state, new_state}
      end

      def play(pid), do: change_playback_state(pid, :playing)
      def prepare(pid), do: change_playback_state(pid, :prepared)
      def stop(pid), do: change_playback_state(pid, :stopped)

      def handle_call({:membrane_change_playback_state, new_state}, _from, state) do
        use Membrane.Helper
        playback_states = %{0 => :stopped, 1 => :prepared, 2 => :playing}
        playback_states_pos = playback_states |> Enum.into(%{}, fn {k, v} -> {v, k} end)

        old_state = state |> current_playback_state
        with \
          {:ok, old_pos} <- playback_states_pos[old_state] ~> (nil -> :invalid_old_playback; v -> {:ok, v}),
          {:ok, new_pos} <- playback_states_pos[new_state] ~> (nil -> :invalid_new_playback; v -> {:ok, v}),
          {:ok, state} <- old_pos..new_pos
            |> Enum.chunk(2, 1)
            |> Helper.Enum.reduce_with(state, fn [i, j], st ->
                handle_playback_state playback_states[i], playback_states[j], st
              end)
        do {:reply, :ok, state}
        else
          :invalid_old_playback -> warn_error """
            Cannot change playback state, because current_playback_state callback
            returned invalid playback state: #{inspect old_state}
            """, :invalid_old_playback
            ~> (err -> {:reply, err, state})
          :invalid_new_playback -> warn_error """
            Cannot change playback state, because passed
            playback state: #{inspect new_state} is invalid
            """, :invalid_new_playback
            ~> (err -> {:reply, err, state})
          {:error, {reason, st}} -> warn_error """
            Unable to change playback state from #{inspect old_state} to #{inspect new_state}
            """, reason
            ~> (err -> {:reply, err, st})
        end
      end

      defoverridable [
        play: 1,
        prepare: 1,
        stop: 1,
      ]

    end
  end

end
