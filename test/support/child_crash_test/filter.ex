defmodule Membrane.Support.ChildCrashTest.Filter do
  @moduledoc """
  Filter used in child crash test.
  Can be crashed on demand by sending `:crash` message.
  """

  use Membrane.Filter

  alias Membrane.Pad

  def_output_pad :output, accepted_format: _any, availability: :on_request

  def_input_pad :input, demand_unit: :buffers, accepted_format: _any, availability: :on_request

  @impl true
  def handle_init(_ctx, _opts) do
    state = %{
      input_pads: MapSet.new(),
      output_pads: MapSet.new()
    }

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(name, _ref) = pad, _ctx, state) do
    key =
      case name do
        :output -> :output_pads
        :input -> :input_pads
      end

    state = Map.update!(state, key, &MapSet.put(&1, pad))

    {[], state}
  end

  @impl true
  def handle_demand(Pad.ref(:output, _pad_ref), size, _unit, _ctx, state) do
    demands =
      state.input_pads
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
  def handle_buffer(_pad, buf, _ctx, state) do
    actions =
      for pad <- state.output_pads do
        {:buffer, {pad, buf}}
      end

    {actions, state}
  end

  @impl true
  def handle_end_of_stream(pad, _ctx, state) do
    {[], %{state | input_pads: MapSet.delete(state.input_pads, pad)}}
  end

  @spec crash(pid()) :: any()
  def crash(pid) do
    send(pid, :crash)
  end
end
