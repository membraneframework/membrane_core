defmodule Membrane.Support.Distributed do
  @moduledoc false

  defmodule SomeStreamFormat do
    @moduledoc false
    defstruct []
  end

  defmodule Source do
    @moduledoc false
    use Membrane.Source

    def_output_pad :output, accepted_format: _any, flow_control: :push
    def_options output: [spec: list(any())]

    @impl true
    def handle_init(_ctx, opts) do
      {[], opts.output}
    end

    @impl true
    def handle_playing(_ctx, list) do
      stream_format = %SomeStreamFormat{}

      {[
         stream_format: {:output, stream_format},
         start_timer: {:timer, Membrane.Time.milliseconds(100)}
       ], list}
    end

    @impl true
    def handle_tick(_timer_id, _context, [first | rest]) do
      {[buffer: {:output, %Membrane.Buffer{payload: first}}], rest}
    end

    @impl true
    def handle_tick(_timer_id, _context, []) do
      {[end_of_stream: :output, stop_timer: :timer], []}
    end
  end

  defmodule Sink do
    @moduledoc false

    use Membrane.Sink

    def_input_pad :input, flow_control: :manual, accepted_format: _any, demand_unit: :buffers

    @impl true
    def handle_playing(_ctx, state) do
      {[demand: {:input, 1}], state}
    end

    @impl true
    def handle_buffer(_pad, _buffer, _ctx, state) do
      {[demand: {:input, 1}], state}
    end
  end
end
