defmodule Membrane.Core.Parent do
  use Membrane.Core.PlaybackHandler

  alias Membrane.Core
  alias Core.{Message, PlaybackHandler}

  require Membrane.PlaybackState
  require Message

  def handle_playback_state(_old, new, state) do
    children_pids =
      state
      |> Core.Parent.ChildrenModel.get_children()
      |> Map.values()

    children_pids
    |> Enum.each(&change_playback_state(&1, new))

    state = %{state | pending_pids: children_pids |> MapSet.new()}
    PlaybackHandler.suspend_playback_change(state)
  end

  @impl PlaybackHandler
  def handle_playback_state_changed(_old, :stopped, %{terminating?: true} = state) do
    Message.self(:stop_and_terminate)
    {:ok, state}
  end

  def handle_playback_state_changed(_old, _new, state), do: {:ok, state}

  @spec change_playback_state(pid, Membrane.PlaybackState.t()) :: :ok
  def change_playback_state(pid, new_state)
      when Membrane.PlaybackState.is_playback_state(new_state) do
    Message.send(pid, :change_playback_state, new_state)
    :ok
  end
end
