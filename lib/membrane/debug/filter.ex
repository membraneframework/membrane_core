defmodule Membrane.Debug.Filter do
  @moduledoc """
  Membrane Filter, that can be used to create a child that will be used to debug data flowing thouth pipeline.

  Any buffers, stream formats and events arriving to #{__MODULE__} will be forwarded by it to the opposite
  side than the one from which they came.

  Usage example:
  ```elixir
  child(:source, CustomSource)
  |> child(:filter, %Membrane.Debug.Filter{
    handle_buffer: &IO.inspect(&1, label: "buffer"),
    handle_stream_format: &IO.inspect(&1, label: "stream format")
  })
  |> child(:sink, CustomSink)
  ```
  """

  use Membrane.Filter

  alias Membrane.Buffer
  alias Membrane.Event
  alias Membrane.StreamFormat

  def_input_pad :input, accepted_format: _any, flow_control: :auto
  def_output_pad :output, accepted_format: _any, flow_control: :auto

  @spec noop(any()) :: :ok
  def noop(_arg \\ nil), do: :ok

  def_options handle_start_of_stream: [
                spec: (-> any()),
                default: &__MODULE__.noop/0,
                description: """
                Function with arity 0, that will be called when the start of stream is received on the input pad.
                Result of this function is ignored.
                """
              ],
              handle_buffer: [
                spec: (Buffer.t() -> any()),
                default: &__MODULE__.noop/1,
                description: """
                Function with arity 1, that will be called with all buffers handled by this sink.
                Result of this function is ignored.
                """
              ],
              handle_event: [
                spec: (Event.t() -> any()),
                default: &__MODULE__.noop/1,
                description: """
                Function with arity 1, that will be called with all events handled by this sink.
                Result of this function is ignored.
                """
              ],
              handle_stream_format: [
                spec: (StreamFormat.t() -> any()),
                default: &__MODULE__.noop/1,
                description: """
                Function with arity 1, that will be called with all stream formats handled by this sink.
                Result of this function is ignored.
                """
              ],
              handle_end_of_stream: [
                spec: (-> any()),
                default: &__MODULE__.noop/0,
                description: """
                Function with arity 0, that will be called when the end of stream is received on the input pad.
                Result of this function is ignored.
                """
              ]

  @impl true
  def handle_init(_ctx, opts) do
    {[], Map.from_struct(opts)}
  end

  @impl true
  def handle_start_of_stream(:input, _ctx, state) do
    _ignored = state.handle_start_of_stream.()
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    _ignored = state.handle_buffer.(buffer)
    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_event(_pad, event, _ctx, state) do
    _ignored = state.handle_event.(event)
    {[forward: event], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    _ignored = state.handle_stream_format.(stream_format)
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    _ignored = state.handle_end_of_stream.()
    {[end_of_stream: :output], state}
  end
end
