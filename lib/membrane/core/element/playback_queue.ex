defmodule Membrane.Core.Element.PlaybackQueue do
  @moduledoc false

  alias Membrane.Core.Element.State

  @type t :: [(State.t() -> State.t())]

  @spec store((State.t() -> State.t()), State.t()) :: State.t()
  def store(function, %State{playback_queue: playback_queue} = state) do
    %State{state | playback_queue: [function | playback_queue]}
  end

  @spec eval(State.t()) :: State.t()
  def eval(%State{playback_queue: playback_queue} = state) do
    state =
      playback_queue
      |> List.foldr(state, fn function, state ->
        state = function.(state)
        if state == :input, do: IO.inspect(state, label: "DUPA #{inspect(function)}")
        state
      end)

    %State{state | playback_queue: []}
  end
end
