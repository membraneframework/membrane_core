defmodule Membrane.Support.ChildCrashTest.Filter do
  @moduledoc """
  Filter used in child crash test.
  Can be crashed on demand by sending `:crash` message.
  """

  use Membrane.Filter

  def_output_pad :output, accepted_format: _any

  def_input_pad :input, demand_unit: :buffers, accepted_format: _any, availability: :on_request

  @impl true
  def handle_init(_ctx, _opts) do
    {[], Map.put(%{}, :pads, MapSet.new())}
  end

  @impl true
  def handle_pad_added(pad, _ctx, state) do
    {[], %{state | pads: MapSet.put(state.pads, pad)}}
  end

  @impl true
  def handle_demand(:output, size, _unit, _ctx, state) do
    demands =
      state.pads
      |> Enum.map(fn pad -> {:demand, {pad, size}} end)

    {demands, state}
  end

  @impl true
  def handle_info(:crash, _ctx, state) do
    # code that will cause crash of the filter
    Process.exit(self(), :crash)

    {[], state}
  end

  @impl true
  def handle_process(_pad, buf, _ctx, state) do
    {[buffer: {:output, buf}], state}
  end

  @impl true
  def handle_end_of_stream(pad, _ctx, state) do
    {[], %{state | pads: MapSet.delete(state.pads, pad)}}
  end

  @spec crash(pid()) :: any()
  def crash(pid) do
    send(pid, :crash)
  end
end
