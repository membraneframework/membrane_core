defmodule Membrane.Support.Distributed do
  @moduledoc false
  defmodule Source do
    @moduledoc false
    use Membrane.Source

    def_output_pad :output, caps: :any, mode: :push

    @impl true
    def handle_init(_opts) do
      {:ok, %{}}
    end

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      {{:ok, caps: {:output, :some}, start_timer: {:timer, Membrane.Time.milliseconds(100)}},
       state}
    end

    @impl true
    def handle_tick(_timer_id, _context, state) do
      {{:ok, buffer: {:output, %Membrane.Buffer{payload: "Test buffer"}}}, state}
    end
  end

  defmodule Sink do
    @moduledoc false

    use Membrane.Sink

    def_input_pad :input, caps: :any, demand_unit: :buffers, mode: :pull

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      {{:ok, demand: {:input, 1}}, state}
    end

    @impl true
    def handle_write(_pad, _buffer, _ctx, state) do
      {{:ok, demand: {:input, 1}}, state}
    end
  end
end
