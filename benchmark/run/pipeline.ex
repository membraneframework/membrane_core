defmodule Benchmark.Run.Pipeline do
  @moduledoc false
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, options) do
    {[spec: options[:spec]], %{monitoring_process: options[:monitoring_process]}}
  end

  @impl true
  def handle_call(:get_filters_memory, ctx, state) do

    {[reply: 1], state}
  end

  @impl true
  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    send(state.monitoring_process, :sink_eos)
    {[], state}
  end

  def handle_element_end_of_stream(_not_sink, _pad, _ctx, state) do

    {[], state}
  end
end
