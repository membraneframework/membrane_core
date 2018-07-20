defmodule Membrane.Support.Element.TrivialSink do
  @moduledoc """
  This is minimal sample sink element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Element.Base.Sink

  def_known_sink_pads sink: {:always, {:pull, demand_in: :buffers}, :any}

  @impl true
  def handle_init(_options) do
    {:ok, %{timer: nil}}
  end

  @impl true
  def handle_prepare(:stopped, %Ctx.Prepare{}, state), do: {:ok, state}

  def handle_prepare(:playing, %Ctx.Prepare{}, %{timer: timer}) do
    if timer do
      :timer.cancel(timer)
    end

    {:ok, %{timer: nil}}
  end

  @impl true
  def handle_play(%Ctx.Play{}, state) do
    {:ok, timer} = :timer.send_interval(500, :tick)
    {:ok, %{state | timer: timer}}
  end

  @impl true
  def handle_other(:tick, %Ctx.Other{}, state) do
    {{:ok, demand: {:sink, 2}}, state}
  end

  @impl true
  def handle_write1(:sink, _buf, %Ctx.Write{}, state) do
    {:ok, state}
  end
end
