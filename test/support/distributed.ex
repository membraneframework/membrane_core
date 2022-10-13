defmodule Membrane.Support.Distributed do
  @moduledoc false
  defmodule Source do
    @moduledoc false
    use Membrane.Source

    def_output_pad :output, caps: :any, mode: :push
    def_options output: [spec: list(any())]

    @impl true
    def handle_init(opts) do
      {:ok, opts.output}
    end

    @impl true
    def handle_playing(_ctx, list) do
      {{:ok, caps: {:output, :some}, start_timer: {:timer, Membrane.Time.milliseconds(100)}},
       list}
    end

    @impl true
    def handle_tick(_timer_id, _context, [first | rest]) do
      {{:ok, buffer: {:output, %Membrane.Buffer{payload: first}}}, rest}
    end

    @impl true
    def handle_tick(_timer_id, _context, []) do
      {{:ok, end_of_stream: :output, stop_timer: :timer}, []}
    end
  end

  defmodule Sink do
    @moduledoc false

    use Membrane.Sink

    def_input_pad :input, caps: :any, demand_unit: :buffers, mode: :pull

    @impl true
    def handle_playing(_ctx, state) do
      {{:ok, demand: {:input, 1}}, state}
    end

    @impl true
    def handle_write(_pad, _buffer, _ctx, state) do
      {{:ok, demand: {:input, 1}}, state}
    end
  end
end
