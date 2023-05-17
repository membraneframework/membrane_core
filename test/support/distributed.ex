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

  defmodule SinkBin do
    use Membrane.Bin

    def_input_pad :input, accepted_format: _any

    @impl true
    def handle_init(_ctx, _opts) do
      spec =
        bin_input()
        |> via_in(:input, toilet_capacity: 100, throttling_factor: 50)
        |> child(:sink, Sink)

      {[spec: spec], %{}}
    end

    @impl true
    def handle_element_end_of_stream(:sink, :input, _ctx, state) do
      {[notify_parent: :end_of_stream], state}
    end
  end

  defmodule Pipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, opts) do
      first_node = opts.first_node
      second_node = opts.second_node

      {[
         spec: [
           {child(:source, %Source{output: [1, 2, 3, 4, 5]}), node: first_node},
           {
             get_child(:source) |> child(:sink_bin, SinkBin),
             node: second_node
           }
         ]
       ], %{}}
    end
  end
end
