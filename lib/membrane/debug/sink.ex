defmodule Membrane.Debug.Sink do
  @moduledoc """
  Membrane Sink, that can be used to create a child that will be used to debug data flowing thouth pipeline.

  Usage example:
  ```elixir
  child(:source, CustomSource)
  |> child(:sink, %Membrane.Debug.Sink{
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

  @spec noop(any()) :: :ok
  def noop(_arg), do: :ok

  @spec noop() :: :ok
  def noop(), do: :ok

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

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    _ignored = state.handle_end_of_stream.()
    {[], state}
  end
end
