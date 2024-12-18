defmodule Membrane.Tee do
  @moduledoc """
  Element for forwarding buffers to at least one output pad

  It has one input pad `:input` and 2 output pads:
  * `:output` - is a dynamic pad which is always available and works in pull mode
  * `:output_copy` - is a dynamic pad that can be linked to any number of elements (including 0) and works
    in push mode

  The `:output` pads dictate the speed of processing data and any element (or elements) connected to
  `:output_copy` pad will receive the same data as all `:output` instances.
  """
  use Membrane.Filter

  require Membrane.Logger

  def_input_pad :input,
    availability: :always,
    flow_control: :auto,
    accepted_format: _any

  def_output_pad :output,
    availability: :on_request,
    flow_control: :auto,
    accepted_format: _any

  def_output_pad :output_copy,
    availability: :on_request,
    flow_control: :push,
    accepted_format: _any

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{stream_format: nil}}
  end

  @impl true
  def handle_playing(ctx, state) do
    if map_size(ctx.pads) < 2 do
      Membrane.Logger.debug("""
      #{inspect(__MODULE__)} enters :playing playback without any output (:output or :output_copy) \
      pads linked.
      """)
    end

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[forward: stream_format], %{state | stream_format: stream_format}}
  end

  @impl true
  def handle_pad_added(Pad.ref(name, _ref) = output_pad, ctx, state)
      when name in [:output, :output_copy] do
    maybe_stream_format =
      case state.stream_format do
        nil -> []
        stream_format -> [stream_format: {output_pad, stream_format}]
      end

    maybe_eos =
      if ctx.pads.input.end_of_stream?,
        do: [end_of_stream: output_pad],
        else: []

    {maybe_stream_format ++ maybe_eos, state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    {[forward: buffer], state}
  end
end
