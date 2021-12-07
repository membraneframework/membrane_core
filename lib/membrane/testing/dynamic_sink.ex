defmodule Membrane.Testing.DynamicSink do
  @moduledoc """
  Sink Element that notifies the pipeline about buffers and events it receives. The
  difference between this and `Membrane.Testing.Sink` is that input input pads are
  dynamic.

  By default `DynamicSink` will demand buffers automatically, but you can override that
  behaviour by using `autodemand` option. If set to false no automatic demands
  shall be made. Demands can be then triggered by sending `{:make_demand, size}`
  message.

  This element can be used in conjunction with `Membrane.Testing.Pipeline` to
  enable asserting on buffers and events it receives.

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

  use Membrane.Sink

  def_input_pad :input,
    availability: :on_request,
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
    {:ok, %{autodemand: opts.autodemand, pad: nil}}
  end

  @impl true
  def handle_pad_added(pad, _context, state) do
    {:ok, %{state | pad: pad}}
  end

  @impl true
  def handle_prepared_to_playing(_context, %{autodemand: true} = state),
    do: {{:ok, demand: state.pad}, state}

  def handle_prepared_to_playing(_context, state), do: {:ok, state}

  @impl true
  def handle_event(_pad, event, _context, state) do
    {{:ok, notify: {:event, event}}, state}
  end

  @impl true
  def handle_start_of_stream(pad, _ctx, state),
    do: {{:ok, notify: {:start_of_stream, pad}}, state}

  @impl true
  def handle_end_of_stream(pad, _ctx, state),
    do: {{:ok, notify: {:end_of_stream, pad}}, state}

  @impl true
  def handle_caps(pad, caps, _context, state),
    do: {{:ok, notify: {:caps, pad, caps}}, state}

  @impl true
  def handle_write(pad, buf, _ctx, state) do
    case state do
      %{autodemand: false} -> {{:ok, notify: {:buffer, buf}}, state}
      %{autodemand: true} -> {{:ok, demand: pad, notify: {:buffer, buf}}, state}
    end
  end
end
