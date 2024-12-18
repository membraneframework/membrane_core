defmodule Membrane.Tee.Parallel do
  @moduledoc """
  Element for forwarding packets to multiple outputs.

  The processing speed is limited by the slowest consuming output.

  To use, link this element to one preceding element via `input` pad and multiple
  succesive elements via `output` pads. Each buffer is forwarded only when demand for
  it comes in via each output. If there are no outputs, buffers are dropped.
  """

  use Membrane.Filter

  def_input_pad :input,
    availability: :always,
    flow_control: :auto,
    accepted_format: _any

  def_output_pad :output,
    availability: :on_request,
    flow_control: :auto,
    accepted_format: _any

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{accepted_format: nil}}
  end

  @impl true
  def handle_stream_format(_pad, accepted_format, _ctx, state) do
    {[forward: accepted_format], %{state | accepted_format: accepted_format}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, _ref), _ctx, %{accepted_format: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_pad_added(pad, _ctx, %{accepted_format: accepted_format} = state) do
    {[stream_format: {pad, accepted_format}], state}
  end

  @impl true
  def handle_buffer(:input, %Membrane.Buffer{} = buffer, _ctx, state) do
    {[forward: buffer], state}
  end
end
