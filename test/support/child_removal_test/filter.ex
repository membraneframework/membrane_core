defmodule Membrane.Support.ChildRemovalTest.Filter do
  @moduledoc """
  Module used in tests for elements removing.

  It allows to:
  * slow down the moment of switching to :playing.
  * send demands and buffers from two input pads to one output pad.

  Should be used along with `Membrane.Support.ChildRemovalTest.Pipeline` as they
  share names (i.e. input_pads: `input1` and `input2`) and exchanged messages' formats.
  """

  use Membrane.Filter

  def_output_pad :output, flow_control: :manual, accepted_format: _any, availability: :on_request

  def_input_pad :input1,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: _any,
    availability: :on_request

  def_input_pad :input2,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: _any,
    availability: :on_request

  def_options demand_generator: [
                spec: (pos_integer -> non_neg_integer),
                default: &__MODULE__.default_demand_generator/1
              ],
              playing_delay: [spec: integer(), default: 0]

  @impl true
  def handle_init(_ctx, opts) do
    {[], Map.put(opts, :pads, MapSet.new())}
  end

  @impl true
  def handle_pad_added(pad, _ctx, state) do
    new_pads = MapSet.put(state.pads, pad)
    {[], %{state | pads: new_pads}}
  end

  @impl true
  def handle_pad_removed(pad, _ctx, state) do
    new_pads = MapSet.delete(state.pads, pad)
    {[], %{state | pads: new_pads}}
  end

  @impl true
  def handle_playing(_ctx, %{playing_delay: time} = state) do
    Process.sleep(time)
    {[notify_parent: :playing], state}
  end

  @impl true
  def handle_demand(_output, size, _unit, ctx, state) do
    demands =
      ctx.pads
      |> Map.values()
      |> Enum.filter(&(&1.direction == :input))
      |> Enum.map(fn pad -> {:demand, {pad.ref, state.demand_generator.(size)}} end)

    {demands, state}
  end

  @impl true
  def handle_buffer(_input, buf, ctx, state) do
    buffers =
      ctx.pads
      |> Map.values()
      |> Enum.filter(&(&1.direction == :output))
      |> Enum.map(&{:buffer, {&1.ref, buf}})

    {buffers, state}
  end

  @impl true
  def handle_end_of_stream(pad, _ctx, state) do
    {[], %{state | pads: MapSet.delete(state.pads, pad)}}
  end

  @spec default_demand_generator(integer()) :: integer()
  def default_demand_generator(demand), do: demand
end
