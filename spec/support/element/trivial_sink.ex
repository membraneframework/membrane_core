defmodule Membrane.Support.Element.TrivialSink do
  @moduledoc """
  This is minimal sample sink element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Element.Base.Sink

  def_known_sink_pads %{
    :sink => {:always, {:pull, demand_in: :buffers}, :any}
  }

  def handle_init(_options) do
    {:ok, %{timer: nil}}
  end

  def handle_prepare(:stopped, state), do: {:ok, state}

  def handle_prepare(:playing, %{timer: timer}) do
    if timer do
      :timer.cancel(timer)
    end

    {:ok, %{timer: nil}}
  end

  def handle_play(state) do
    {:ok, timer} = :timer.send_interval(500, :tick)
    {:ok, %{state | timer: timer}}
  end

  def handle_other(:tick, state) do
    {{:ok, [{:demand, {:sink, 2}}]}, state}
  end

  def handle_write1(:sink, _buf, _, state) do
    {:ok, state}
  end
end
