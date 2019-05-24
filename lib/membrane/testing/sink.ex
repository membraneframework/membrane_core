defmodule Membrane.Testing.Sink do
  @moduledoc """
  Sink Element that allows asserting on buffers it receives.

      alias Membrane.Testing
      {:ok, pid} = Testing.Pipeline.start_link(Testing.Pipeline.Options{
        elements: [
          ...,
          sink: %Testing.Sink{}
        ]
      })

  Asserting that `Membrane.Testing.Sink` element processed a buffer that matches
  a specific pattern can be achieved using
  `Membrane.Testing.Assertions.assert_sink_buffer/3`.

      assert_sink_buffer(pid, :sink ,%Membrane.Buffer{payload: 255})
  """

  use Membrane.Element.Base.Sink

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
    {{:ok, notify: {:event, event}}, state}
  end

  @impl true
  def handle_other({:make_demand, size}, _ctx, %{autodemand: false} = state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_write(:input, buf, _ctx, state) do
    case state do
      %{autodemand: false} -> {{:ok, notify: {:buffer, buf}}, state}
      %{autodemand: true} -> {{:ok, demand: :input, notify: {:buffer, buf}}, state}
    end
  end
end
