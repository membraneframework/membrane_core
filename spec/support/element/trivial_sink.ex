defmodule Membrane.Support.Element.TrivialSink do
  @moduledoc """
  This is minimal sample sink element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Element.Base.Sink

  def_input_pads input: [caps: :any, demand_unit: :buffers]

  @impl true
  def handle_init(_options) do
    {:ok, %{timer: nil}}
  end

  @impl true
  def handle_stopped_to_prepared(%Ctx.PlaybackChange{}, state), do: {:ok, state}

  def handle_playing_to_prepared(%Ctx.PlaybackChange{}, %{timer: timer}) do
    if timer do
      :timer.cancel(timer)
    end

    {:ok, %{timer: nil}}
  end

  @impl true
  def handle_prepared_to_playing(%Ctx.PlaybackChange{}, state) do
    {:ok, timer} = :timer.send_interval(500, :tick)
    {:ok, %{state | timer: timer}}
  end

  @impl true
  def handle_other(:tick, %Ctx.Other{}, state) do
    {{:ok, demand: {:input, 2}}, state}
  end

  @impl true
  def handle_write(:input, _buf, %Ctx.Write{}, state) do
    {:ok, state}
  end
end
