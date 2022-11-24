defmodule Membrane.Testing.Sink do
  @moduledoc """
  Sink Element that notifies the pipeline about buffers and events it receives.

  By default `Sink` will demand buffers automatically, but you can override that
  behaviour by using `autodemand` option. If set to false no automatic demands
  shall be made. Demands can be then triggered by sending `{:make_demand, size}`
  message.

  This element can be used in conjunction with `Membrane.Testing.Pipeline` to
  enable asserting on buffers and events it receives.

      alias Membrane.Testing
      links = [
          ... |>
          child(:sink, %Testing.Sink{}) |>
          ...
      ]
      {:ok, pid} = Testing.Pipeline.start_link(
        structure: links
      )

  Asserting that `Membrane.Testing.Sink` element processed a buffer that matches
  a specific pattern can be achieved using
  `Membrane.Testing.Assertions.assert_sink_buffer/3`.

      assert_sink_buffer(pid, :sink ,%Membrane.Buffer{payload: 255})

  """

  use Membrane.Sink

  alias Membrane.Testing.Notification

  def_input_pad :input,
    demand_unit: :buffers,
    accepted_format: _any

  def_options autodemand: [
                spec: boolean(),
                default: true,
                description: """
                If true element will automatically make demands.
                If it is set to false demand has to be triggered manually by sending `:make_demand` message.
                """
              ]

  @impl true
  def handle_init(_ctx, opts) do
    {[], opts}
  end

  @impl true
  def handle_playing(_context, %{autodemand: true} = state),
    do: {[demand: :input], state}

  def handle_playing(_context, state), do: {[], state}

  @impl true
  def handle_event(:input, event, _context, state) do
    {notify({:event, event}), state}
  end

  @impl true
  def handle_start_of_stream(pad, _ctx, state),
    do: {notify({:start_of_stream, pad}), state}

  @impl true
  def handle_end_of_stream(pad, _ctx, state),
    do: {notify({:end_of_stream, pad}), state}

  @impl true
  def handle_stream_format(pad, stream_format, _context, state),
    do: {notify({:stream_format, pad, stream_format}), state}

  @impl true
  def handle_parent_notification({:make_demand, size}, _ctx, %{autodemand: false} = state) do
    {[demand: {:input, size}], state}
  end

  @impl true
  def handle_write(:input, buf, _ctx, state) do
    case state do
      %{autodemand: false} -> {notify({:buffer, buf}), state}
      %{autodemand: true} -> {[demand: :input] ++ notify({:buffer, buf}), state}
    end
  end

  defp notify(payload) do
    [notify_parent: %Notification{payload: payload}]
  end
end
