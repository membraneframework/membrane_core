defmodule Membrane.Support.Distributed do
  alias Membrane.ParentSpec

  defmodule Source do
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
      {{:ok, buffer: {:output, %Membrane.Buffer{payload: "XD"}}}, state}
    end
  end

  defmodule Sink do
    use Membrane.Sink

    def_input_pad :input, caps: :any, demand_unit: :buffers, mode: :pull

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      IO.inspect("HANDLE PREPARED TO PLAYING")
      {{:ok, demand: {:input, 1}}, state}
    end

    @impl true
    def handle_write(_pad, buffer, _ctx, state) do
      IO.inspect(buffer, label: "BUFFER")

      {{:ok, demand: {:input, 1}}, state}
    end
  end

  defmodule Pipeline do
    use Membrane.Pipeline
    require Membrane.ParentSpec

    @impl true
    def handle_init(_opts) do
      {
        {:ok,
         spec: %ParentSpec{
           children: [
             source: MySource
           ],
           node: :"node1@127.0.0.1"
         },
         spec: %ParentSpec{
           children: [sink: Membrane.Testing.Sink],
           links: [
             link(:source)
             |> via_in(:input, toilet_capacity: 100, throttling_factor: 50)
             |> to(:sink)
           ],
           node: :"node2@127.0.0.1"
         },
         playback: :playing},
        %{}
      }
    end
  end
end
