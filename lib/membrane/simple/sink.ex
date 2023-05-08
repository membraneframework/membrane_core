defmodule Membrane.Simple.Sink do
  @moduledoc """
  Simple Membrane Sink, that can be used to create inlined children implementation.

  Accepts 3 options:
   - `:handle_buffer` - function with arity 1, that will be called with all buffers handled by this sink
   - `:handle_event` - function with arity 1, that will be called with all events handled by this sink
   - `:handle_stream_format` - function with arity 1, that will be called with all stream formats handled by this sink

  Usage example:
  ```elixir
  child(:source, CustomSource)
  |> child(:sink, %Membrane.Simple.Sink{
    handle_buffer: &IO.inspect(&1, label: "buffer"),
    handle_event: &IO.inspect(&1, label: "event")
  })
  ```
  """

  use Membrane.Sink

  alias Membrane.Buffer
  alias Membrane.Event
  alias Membrane.StreamFormat

  def_input_pad :input, accepted_format: _any, flow_control: :auto

  def_options handle_buffer: [spec: (Buffer.t() -> any()), default: & &1],
              handle_event: [spec: (Event.t() -> any()), default: & &1],
              handle_stream_format: [spec: (StreamFormat.t() -> any()), default: & &1]

  @impl true
  def handle_init(_ctx, opts) do
    {[], Map.new(opts)}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    _ignored = state.handle_buffer.(buffer)
    {[], state}
  end

  @impl true
  def handle_event(:input, event, _ctx, state) do
    _ignored = state.handle_event.(event)
    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    _ignored = state.handle_stream_format.(stream_format)
    {[], state}
  end
end
