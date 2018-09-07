defmodule Membrane.Support.Element.TrivialSink do
  @moduledoc """
  This is minimal sample sink element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Element.Base.Sink

  def_sink_pads sink: {:always, {:pull, demand_in: :buffers}, :any}

  @impl true
  def handle_init(_options) do
    {:ok, %{timer: nil}}
  end

  @impl true
  def handle_stopped_to_prepared(%Ctx.StateChange{}, state), do: {:ok, state}

  def handle_playing_to_prepared(%Ctx.StateChange{}, %{timer: timer}) do
    if timer do
      :timer.cancel(timer)
    end

    {:ok, %{timer: nil}}
  end

  @impl true
  def handle_prepared_to_playing(%Ctx.StateChange{}, state) do
    {:ok, timer} = :timer.send_interval(500, :tick)
    {:ok, %{state | timer: timer}}
  end

  @impl true
  def handle_other(:tick, %Ctx.Other{}, state) do
    {{:ok, demand: {:sink, 2}}, state}
  end

  @impl true
  def handle_write(:sink, _buf, %Ctx.Write{}, state) do
    {:ok, state}
  end
end
