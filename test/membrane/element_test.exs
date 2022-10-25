defmodule Membrane.ElementTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  defmodule TestFilter do
    use Membrane.Filter

    def_input_pad :input, caps: _any, demand_unit: :buffers

    def_output_pad :output, caps: _any

    def_options target: [type: :pid]

    @spec assert_callback_called(atom) :: :ok
    def assert_callback_called(name) do
      assert_receive {:callback_called, ^name}
      :ok
    end

    @spec refute_callback_called(atom) :: :ok
    def refute_callback_called(name) do
      refute_receive {:callback_called, ^name}
      :ok
    end

    @impl true
    def handle_init(opts), do: {:ok, opts}

    @impl true
    def handle_playing(_ctx, state) do
      send(state.target, {:callback_called, :handle_playing})
      {:ok, state}
    end

    @impl true
    def handle_start_of_stream(_pad, _context, state) do
      send(state.target, {:callback_called, :handle_start_of_stream})
      {:ok, state}
    end

    @impl true
    def handle_end_of_stream(_pad, _context, state) do
      send(state.target, {:callback_called, :handle_end_of_stream})
      {:ok, state}
    end

    @impl true
    def handle_event(_pad, _event, _context, state) do
      send(state.target, {:callback_called, :handle_event})
      {:ok, state}
    end

    @impl true
    def handle_demand(_pad, size, _unit, _context, state) do
      {{:ok, demand: {:input, size}}, state}
    end

    @impl true
    def handle_process(_pad, _buffer, _context, state), do: {:ok, state}
  end

  setup do
    links = [
      child(:source, %Testing.Source{output: ['a', 'b', 'c']})
      |> child(:filter, %TestFilter{target: self()})
      |> child(:sink, Testing.Sink)
    ]

    pipeline = Testing.Pipeline.start_link_supervised!(structure: links)

    [pipeline: pipeline]
  end

  test "play", %{pipeline: pipeline} do
    assert_pipeline_play(pipeline)
    TestFilter.assert_callback_called(:handle_playing)
  end

  describe "Start of stream" do
    test "causes handle_start_of_stream/3 to be called", %{pipeline: pipeline} do
      assert_pipeline_play(pipeline)

      TestFilter.assert_callback_called(:handle_start_of_stream)
    end

    test "does not trigger calling callback handle_event/3", %{pipeline: pipeline} do
      assert_pipeline_play(pipeline)

      TestFilter.refute_callback_called(:handle_event)
    end

    test "causes handle_element_start_of_stream/4 to be called in pipeline", %{pipeline: pipeline} do
      assert_start_of_stream(pipeline, :filter)
    end
  end

  describe "End of stream" do
    test "causes handle_end_of_stream/3 to be called", %{pipeline: pipeline} do
      assert_pipeline_play(pipeline)

      TestFilter.assert_callback_called(:handle_end_of_stream)
    end

    test "does not trigger calling callback handle_event/3", %{pipeline: pipeline} do
      assert_pipeline_play(pipeline)

      TestFilter.refute_callback_called(:handle_event)
    end

    test "causes handle_element_end_of_stream/4 to be called in pipeline", %{pipeline: pipeline} do
      assert_end_of_stream(pipeline, :filter)
    end
  end
end
