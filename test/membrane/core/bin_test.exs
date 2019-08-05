defmodule Membrane.Core.BinTest do
  use ExUnit.Case, async: true

  alias Membrane.Bin
  alias Membrane.Testing

  import Membrane.Testing.Assertions

  defmodule TestBin do
    use Membrane.Bin

    def_options filter1: [type: :atom],
                filter2: [type: :atom]

    def_input_pad :input, demand_unit: :buffers, caps: :any

    def_output_pad :output, caps: :any

    @impl true
    def handle_init(opts) do
      children = [
        filter1: opts.filter1,
        filter2: opts.filter2
      ]

      links = %{
        {this_bin(), :input} => {:filter1, :input, buffer: [preferred_size: 10]},
        {:filter1, :output} => {:filter2, :input, buffer: [preferred_size: 10]},
        {:filter2, :output} => {this_bin(), :output, buffer: [preferred_size: 10]}
      }

      spec = %Membrane.Bin.Spec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec}, state}
    end

    def handle_spec_started(elements, state) do
      {:ok, state}
    end

    def handle_stopped_to_prepared(state), do: {:ok, state}

    def handle_prepared_to_playing(state), do: {:ok, state}
  end

  defmodule TestFilter do
    alias Membrane.Event.StartOfStream

    use Membrane.Filter

    def_output_pad :output, caps: :any

    def_input_pad :input, demand_unit: :buffers, caps: :any

    @impl true
    def handle_init(opts), do: {:ok, opts}

    @impl true
    def handle_prepared_to_playing(_ctx, state), do: {:ok, state}

    @impl true
    def handle_demand(:output, size, _, _ctx, state), do: {{:ok, demand: {:input, size}}, state}

    @impl true
    def handle_process(_pad, buf, _, state), do: {{:ok, buffer: {:output, buf}}, state}

    @impl true
    def handle_event(_pad, event, _ctx, state), do: {{:ok, forward: event}, state}

    @impl true
    def handle_shutdown(_), do: :ok
  end

  test "Bin starts in pipeline and transmits buffers successfully" do
    buffers = ['a', 'b', 'c']

    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        elements: [
          source: %Testing.Source{output: buffers},
          test_bin: %TestBin{
            filter1: TestFilter,
            filter2: TestFilter
          },
          sink: Testing.Sink
        ]
      })

    Testing.Pipeline.play(pipeline) == :ok

    assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)

    assert_start_of_stream(pipeline, :sink)

    buffers
    |> Enum.each(fn b -> assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^b}) end)

    assert_end_of_stream(pipeline, :sink)
  end

  test "Bin next to a bin transmits buffers successfully" do
    buffers = ['a', 'b', 'c']

    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        elements: [
          source: %Testing.Source{output: buffers},
          test_bin1: %TestBin{
            filter1: TestFilter,
            filter2: TestFilter
          },
          test_bin2: %TestBin{
            filter1: TestFilter,
            filter2: TestFilter
          },
          sink: Testing.Sink
        ]
      })

    Testing.Pipeline.play(pipeline) == :ok

    assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)

    assert_start_of_stream(pipeline, :sink)

    buffers
    |> Enum.each(fn b -> assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^b}) end)

    assert_end_of_stream(pipeline, :sink)
  end

  test "Nested bins transmit buffers successfully" do
    buffers = ['a', 'b', 'c']

    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        elements: [
          source: %Testing.Source{output: buffers},
          test_bin: %TestBin{
            filter1: TestFilter,
            filter2: %TestBin{
              filter1: TestFilter,
              filter2: TestFilter
            }
          },
          sink: Testing.Sink
        ]
      })

    Testing.Pipeline.play(pipeline) == :ok

    assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)

    assert_start_of_stream(pipeline, :sink)

    buffers
    |> Enum.each(fn b -> assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^b}) end)

    assert_end_of_stream(pipeline, :sink)
  end
end
