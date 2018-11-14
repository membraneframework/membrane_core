defmodule Membrane.Core.PlaybackRequestor do
  @moduledoc false
  # Behaviour for modules that send playback change requests to processes.
  # `Membrane.Core.PlaybackRequestor` can be used for handling such requests.

  alias Membrane.Core.Playback

  @callback change_playback_state(pid, Playback.state_t()) :: :ok

  defmacro __using__(_args) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)
      require Membrane.Core.Playback

      @doc """
      Changes playback state to `:playing`.

      An alias for `change_playback_state/2` with proper state.
      """
      @spec play(pid) :: :ok
      def play(pid), do: change_playback_state(pid, :playing)

      @doc """
      Changes playback state to `:prepared`.

      An alias for `change_playback_state/2` with proper state.
      """
      @spec prepare(pid) :: :ok
      def prepare(pid), do: change_playback_state(pid, :prepared)

      @doc """
      Changes playback state to `:stopped`.

      An alias for `change_playback_state/2` with proper state.
      """
      @spec stop(pid) :: :ok
      def stop(pid), do: change_playback_state(pid, :stopped)

      @impl unquote(__MODULE__)
      @doc """
      Changes the playback state to the `new_state`.
      """
      @spec change_playback_state(pid, Playback.state_t()) :: :ok
      def change_playback_state(pid, new_state)
          when Membrane.Core.Playback.is_playback_state(new_state) do
        alias Membrane.Core.Message
        require Message
        Message.send(pid, :change_playback_state, new_state)
        :ok
      end

      defoverridable change_playback_state: 2
    end
  end
end
