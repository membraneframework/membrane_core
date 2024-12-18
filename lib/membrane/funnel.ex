defmodule Membrane.Funnel do
  @moduledoc """
  Element that can be used for collecting data from multiple inputs and sending it through one
  output. When a new input connects in the `:playing` state, the funnel sends
  `Membrane.Funnel.NewInputEvent` via output.
  """
  use Membrane.Filter

  alias Membrane.Funnel

  def_input_pad :input, accepted_format: _any, flow_control: :auto, availability: :on_request
  def_output_pad :output, accepted_format: _any, flow_control: :auto

  def_options end_of_stream: [spec: :on_last_pad | :on_first_pad | :never, default: :on_last_pad]

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{end_of_stream: opts.end_of_stream}}
  end

  @impl true
  def handle_buffer(Pad.ref(:input, _id), buffer, _ctx, state) do
    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, _id), %{playback_state: :playing}, state) do
    {[event: {:output, %Funnel.NewInputEvent{}}], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, _id), _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, _id), _ctx, %{end_of_stream: :never} = state) do
    {[], state}
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, _id), ctx, %{end_of_stream: :on_first_pad} = state) do
    if ctx.pads.output.end_of_stream? do
      {[], state}
    else
      {[end_of_stream: :output], state}
    end
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, _id), ctx, %{end_of_stream: :on_last_pad} = state) do
    if ctx |> inputs_data() |> Enum.all?(& &1.end_of_stream?) do
      {[end_of_stream: :output], state}
    else
      {[], state}
    end
  end

  defp inputs_data(ctx) do
    Enum.flat_map(ctx.pads, fn
      {Pad.ref(:input, _id), data} -> [data]
      _output -> []
    end)
  end
end
