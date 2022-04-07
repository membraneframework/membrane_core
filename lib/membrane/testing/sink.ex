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
      children = [
          ...,
          sink: %Testing.Sink{}
      ]
      {:ok, pid} = Testing.Pipeline.start_link(
        children: children,
        links: Membrane.ParentSpec.link_linear(children)
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
    caps: :any

  def_options autodemand: [
                type: :boolean,
                default: true,
                description: """
                If true element will automatically make demands.
                If it is set to false demand has to be triggered manually by sending `:make_demand` message.
                """
              ]

  @impl true
  def handle_init(opts) do
    {:ok, opts}
  end

  @impl true
  def handle_prepared_to_playing(_context, %{autodemand: true} = state),
    do: {{:ok, demand: :input}, state}

  def handle_prepared_to_playing(_context, state), do: {:ok, state}

  @impl true
  def handle_event(:input, event, _context, state) do
    {{:ok, notify({:event, event})}, state}
  end

  @impl true
  def handle_start_of_stream(pad, _ctx, state),
    do: {{:ok, notify({:start_of_stream, pad})}, state}

  @impl true
  def handle_end_of_stream(pad, _ctx, state),
    do: {{:ok, notify({:end_of_stream, pad})}, state}

  @impl true
  def handle_caps(pad, caps, _context, state),
    do: {{:ok, notify({:caps, pad, caps})}, state}

  @impl true
  def handle_parent_notification({:make_demand, size}, %{autodemand: false} = state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_write(:input, buf, _ctx, state) do
    case state do
      %{autodemand: false} -> {{:ok, notify({:buffer, buf})}, state}
      %{autodemand: true} -> {{:ok, [demand: :input] ++ notify({:buffer, buf})}, state}
    end
  end

  defp notify(payload) do
    [notify_parent: %Notification{payload: payload}]
  end
end
