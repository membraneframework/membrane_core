defmodule Membrane.Core.Element.StatusQueue do
  @moduledoc false

  alias Membrane.Core.Element.State

  @spec store((State.t() -> State.t()), State.t()) :: State.t()
  def store(function, %State{status_queue: status_queue} = state) do
    %State{state | status_queue: [function | status_queue]}
  end

  @spec eval(State.t()) :: State.t()
  def eval(%State{status_queue: status_queue} = state) do
    state =
      status_queue
      |> Enum.reverse()
      |> Enum.reduce(state, fn function, state -> function.(state) end)

    %State{state | status_queue: []}
  end
end
