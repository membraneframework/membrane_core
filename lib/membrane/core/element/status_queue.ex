defmodule Membrane.Core.Element.StatusQueue do
  @moduledoc false

  alias Membrane.Core.Element.State

  @spec store((State.t() -> State.t()), State.t()) :: State.t()
  def store(function, %State{status_buffer: status_buffer} = state) do
    %State{state | status_buffer: [function | status_buffer]}
  end

  @spec eval(State.t()) :: State.t()
  def eval(%State{status_buffer: status_buffer} = state) do
    state =
      status_buffer
      |> Enum.reverse()
      |> Enum.reduce(state, fn function, state -> function.(state) end)

    %State{state | status_buffer: []}
  end
end
