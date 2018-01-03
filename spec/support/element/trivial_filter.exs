defmodule Membrane.Support.Element.TrivialFilter do
  @moduledoc """
  This is minimal sample filter element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """


  use Membrane.Element.Base.Filter

  def_known_source_pads %{
    :source => {:always, :pull, :any}
  }


  def_known_sink_pads %{
    :sink => {:always, {:pull, demand_in: :buffers}, :any}
  }

  def handle_init(_options) do
    {:ok, %{}}
  end


  def handle_demand :source, size, _, %Membrane.Element.Context.Demand{}, state do
    {{:ok, [{:demand, {:sink, size}}]}, state}
  end

  def handle_process1 :sink, %Membrane.Buffer{payload: payload}, _, state do
    {{:ok, [buffer: {:source, %Membrane.Buffer{payload: payload <> <<255>>}}]}, state}
  end


end
