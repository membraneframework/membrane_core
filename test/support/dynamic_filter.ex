defmodule Membrane.Support.Element.DynamicFilter do
  @moduledoc """
  This is a mock filter with dynamic inputs for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Bunch
  use Membrane.Filter
  require Membrane.Pad
  alias Membrane.Pad

  def_output_pad :output, caps: :any

  def_input_pad :input, caps: :any, availability: :on_request, demand_unit: :buffers

  def_options pid: [type: :pid]

  @impl true
  def handle_init(_options) do
    {:ok, %{}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, _) = ref, _ctx, state) do
    {:ok, state |> Map.put(:last_pad_addded, ref)}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, _) = ref, _ctx, state) do
    {:ok, state |> Map.put(:last_pad_removed, ref)}
  end

  @impl true
  def handle_demand(_ref, size, _, _ctx, state) do
    {{:ok, demand: {Pad.ref(:input, 0), size}}, state}
  end

  @impl true
  def handle_process(_ref, %Membrane.Buffer{payload: _payload}, %Ctx.Process{}, state) do
    {:ok, state}
  end

  @impl true
  def handle_event(ref, event, _ctx, state) do
    {:ok, state |> Map.put(:last_event, {ref, event})}
  end
end
