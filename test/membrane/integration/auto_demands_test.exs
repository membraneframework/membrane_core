defmodule Membrane.Integration.AutoDemandsTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.Testing.{Pipeline, Sink, Source}

  defmodule AutoDemandFilter do
    use Membrane.Filter

    def_input_pad :input, caps: :any, demand_mode: :auto
    def_output_pad :output, caps: :any, demand_mode: :auto

    def_options factor: [default: 1], direction: [default: :up]

    @impl true
    def handle_init(opts) do
      {:ok, opts |> Map.from_struct() |> Map.merge(%{counter: 1})}
    end

    @impl true
    def handle_process(:input, buffer, _ctx, %{direction: :up} = state) do
      buffers = Enum.map(1..state.factor, fn _i -> buffer end)
      {{:ok, buffer: {:output, buffers}}, state}
    end

    @impl true
    def handle_process(:input, buffer, _ctx, %{direction: :down} = state) do
      if state.counter < state.factor do
        {:ok, %{state | counter: state.counter + 1}}
      else
        {{:ok, buffer: {:output, buffer}}, %{state | counter: 1}}
      end
    end
  end

  defmodule AutoDemandTee do
    use Membrane.Filter

    def_input_pad :input, caps: :any, demand_mode: :auto
    def_output_pad :output, caps: :any, demand_mode: :auto, availability: :on_request

    @impl true
    def handle_process(:input, buffer, _ctx, state), do: {{:ok, forward: buffer}, state}
  end

  [
    %{payloads: 1..100_000, factor: 1, direction: :up, filters: 10},
    %{payloads: 1..4, factor: 10, direction: :up, filters: 5},
    %{payloads: 1..4, factor: 10, direction: :down, filters: 5}
  ]
  |> Enum.map(fn opts ->
    test "buffers pass through auto-demand filters; setup: #{inspect(opts)}" do
      import Membrane.ParentSpec

      %{payloads: payloads, factor: factor, direction: direction, filters: filters} =
        unquote(Macro.escape(opts))

      mult_payloads =
        Enum.flat_map(payloads, &Enum.map(1..Integer.pow(factor, filters), fn _i -> &1 end))

      {in_payloads, out_payloads} =
        case direction do
          :up -> {payloads, mult_payloads}
          :down -> {mult_payloads, payloads}
        end

      filter = %AutoDemandFilter{factor: factor, direction: direction}

      assert {:ok, pipeline} =
               Pipeline.start_link(
                 links: [
                   link(:source, %Source{output: in_payloads})
                   |> reduce_link(1..filters, &to(&1, {:filter, &2}, filter))
                   |> to(:sink, Sink)
                 ]
               )

      assert_pipeline_playback_changed(pipeline, :prepared, :playing)

      Enum.each(out_payloads, fn payload ->
        assert_sink_buffer(pipeline, :sink, buffer)
        assert buffer.payload == payload
      end)

      assert_end_of_stream(pipeline, :sink)
      refute_sink_buffer(pipeline, :sink, _buffer, 0)

      Pipeline.terminate(pipeline, blocking?: true)
    end
  end)

  test "buffers pass through auto-demand tee" do
    import Membrane.ParentSpec

    assert {:ok, pipeline} =
             Pipeline.start_link(
               links: [
                 link(:source, %Source{output: 1..100_000}) |> to(:tee, AutoDemandTee),
                 link(:tee) |> to(:left_sink, Sink),
                 link(:tee) |> to(:right_sink, %Sink{autodemand: false})
               ]
             )

    assert_pipeline_playback_changed(pipeline, :prepared, :playing)
    Pipeline.message_child(pipeline, :right_sink, {:make_demand, 1000})

    Enum.each(1..1000, fn payload ->
      assert_sink_buffer(pipeline, :right_sink, buffer)
      assert buffer.payload == payload
      assert_sink_buffer(pipeline, :left_sink, buffer)
      assert buffer.payload == payload
    end)

    refute_sink_buffer(pipeline, :left_sink, %{payload: 25_000})
    Pipeline.terminate(pipeline, blocking?: true)
  end

  test "handle removed branch" do
    import Membrane.ParentSpec

    assert {:ok, pipeline} =
             Pipeline.start_link(
               links: [
                 link(:source, %Source{output: 1..100_000}) |> to(:tee, AutoDemandTee),
                 link(:tee) |> to(:left_sink, Sink),
                 link(:tee) |> to(:right_sink, %Sink{autodemand: false})
               ]
             )

    assert_pipeline_playback_changed(pipeline, :prepared, :playing)
    Process.sleep(500)
    Pipeline.execute_actions(pipeline, remove_child: :right_sink)

    Enum.each(1..100_000, fn payload ->
      assert_sink_buffer(pipeline, :left_sink, buffer)
      assert buffer.payload == payload
    end)

    Pipeline.terminate(pipeline, blocking?: true)
  end

  defmodule PushSource do
    use Membrane.Source

    def_output_pad :output, mode: :push, caps: :any

    @impl true
    def handle_info(actions, _ctx, state) do
      {{:ok, actions}, state}
    end

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      {{:ok, [caps: {:output, :any}]}, state}
    end
  end

  test "toilet" do
    import Membrane.ParentSpec

    assert {:ok, pipeline} =
             Pipeline.start_link(
               links: [
                 link(:source, PushSource)
                 |> to(:filter, AutoDemandFilter)
                 |> to(:sink, Sink)
               ]
             )

    assert_pipeline_playback_changed(pipeline, :prepared, :playing)
    buffers = Enum.map(1..10, &%Membrane.Buffer{payload: &1})
    Pipeline.message_child(pipeline, :source, buffer: {:output, buffers})

    Enum.each(1..100_010, fn i ->
      assert_sink_buffer(pipeline, :sink, buffer)
      assert buffer.payload == i

      if i <= 100_000 do
        buffer = %Membrane.Buffer{payload: i + 10}
        Pipeline.message_child(pipeline, :source, buffer: {:output, buffer})
      end
    end)

    Pipeline.terminate(pipeline, blocking?: true)
    refute_sink_buffer(pipeline, :sink, _buffer, 0)
  end

  test "toilet overflow" do
    import Membrane.ParentSpec

    assert {:ok, pipeline} =
             Pipeline.start(
               links: [
                 link(:source, PushSource)
                 |> to(:filter, AutoDemandFilter)
                 |> to(:sink, %Sink{autodemand: false})
               ]
             )

    Process.monitor(pipeline)
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)
    buffers = Enum.map(1..100_000, &%Membrane.Buffer{payload: &1})
    Pipeline.message_child(pipeline, :source, buffer: {:output, buffers})
    assert_receive({:DOWN, _ref, :process, ^pipeline, {:shutdown, :child_crash}})
  end

  defp reduce_link(link, enum, fun) do
    Enum.reduce(enum, link, &fun.(&2, &1))
  end
end
