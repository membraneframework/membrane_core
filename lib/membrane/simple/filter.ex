defmodule Membrane.Simple.Filter do
  @moduledoc """
  Simple Membrane Filter, that can be used to create inlined children implementation.

  Accepts 3 options:
   - `:handle_buffer` - function with arity 1, that maps buffers handled by this filter. Defaults to `&(&1)`.
   - `:handle_event` - function with arity 1, that maps events handled by this filter. Defaults to `&(&1)`.
   - `:handle_stream_format` - function with arity 1, that maps stream formats handled by this filter. Defaults to `&(&1)`.

  Usage example:
  ```elixir
  child(:source, CustomSource)
  |> child(:filter, %Membrane.Simple.Filter{
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

  def_options handle_buffer: [spec: (Buffer.t() -> Buffer.t()), default: & &1],
              handle_event: [spec: (Event.t() -> Event.t()), default: & &1],
              handle_stream_format: [spec: (StreamFormat.t() -> StreamFormat.t()), default: & &1]

  @impl true
  def handle_init(_ctx, opts) do
    {[], Map.new(opts)}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    handle_data(:input, buffer, state)
  end

  @impl true
  def handle_event(pad, event, _ctx, state) do
    handle_data(pad, event, state)
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    handle_data(:input, stream_format, state)
  end

  defp handle_data(pad, data, state) do
    opposite_pad =
      case pad do
        :input -> :output
        :output -> :input
      end

    {action, mapper} =
      case data do
        %Buffer{} -> {:buffer, state.handle_buffer}
        %Event{} -> {:event, state.handle_event}
        _stream_format -> {:stream_format, state.handle_stream_format}
      end

    new_data = mapper.(data)

    actions = [{action, {opposite_pad, new_data}}]
    {actions, state}
  end
end
