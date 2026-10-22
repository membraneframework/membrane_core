defmodule Membrane.Support.DemandsTest.ReportingSource do
  @moduledoc false
  use Membrane.Source

  alias Membrane.Buffer

  def_output_pad :output, accepted_format: _any, flow_control: :manual, demand_unit: :buffers

  def_options payloads_count: [spec: pos_integer() | nil, default: nil],
              batch_size: [spec: pos_integer() | nil, default: nil],
              surplus: [spec: non_neg_integer(), default: 0],
              payload: [spec: (pos_integer() -> term()), default: &Function.identity/1]

  @impl true
  def handle_init(_ctx, opts), do: {[], opts |> Map.from_struct() |> Map.put(:produced, 0)}

  @impl true
  def handle_playing(_ctx, state),
    do: {[stream_format: {:output, %Membrane.RemoteStream{}}], state}

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    last_payload =
      last_payload(state.produced + (state.batch_size || size) + state.surplus, state)

    buffers =
      Enum.map((state.produced + 1)..last_payload//1, &%Buffer{payload: state.payload.(&1)})

    continuation =
      if last_payload == state.payloads_count,
        do: [end_of_stream: :output],
        else: [redemand: :output]

    actions = [buffer: {:output, buffers}, notify_parent: {:handle_demand, size, last_payload}]
    {actions ++ continuation, %{state | produced: last_payload}}
  end

  defp last_payload(last_payload, %{payloads_count: nil}), do: last_payload
  defp last_payload(last_payload, state), do: min(last_payload, state.payloads_count)
end
