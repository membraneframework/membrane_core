defmodule Membrane.Integration.LinkingTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  import Membrane.ParentSpec

  alias Membrane.{Buffer, Testing}

  defmodule DynamicSource do
    @moduledoc false
    use Membrane.Source

    def_output_pad :output, caps: :any, availability: :on_request

    def_options output: [
                  spec: List.t(),
                  default: []
                ]

    @impl true
    def handle_init(opts) do
      {:ok, Map.from_struct(opts)}
    end

    @impl true
    def handle_prepared_to_playing(_ctx, state) do
      {{:ok, caps: {:output, state.caps}}, state}
    end

    @impl true
    def handle_demand(:output, 0, :buffers, _ctx, state) do
      {:ok, state}
    end

    @impl true
    def handle_demand(pad, _size, :buffers, _ctx, state) do
      if length(state.output) > 0 do
        [payload | rest] = state.output

        {{:ok,
          [
            {:buffer, {pad, %Buffer{payload: payload}}},
            {:redemand, pad}
          ]}, %{state | output: rest}}
      else
        {{:ok, [end_of_stream: :output]}, state}
      end
    end
  end

  defmodule Pipeline do
    @moduledoc false
    use Membrane.Pipeline

    @impl true
    def handle_init(opts) do
      {:ok, %{testing_pid: opts.testing_pid}}
    end

    @impl true
    def handle_other({:start_spec, %{spec: spec}}, _ctx, state) do
      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_other(
          {:start_spec_and_kill, %{spec: spec, children_to_kill: children_to_kill}},
          ctx,
          state
        ) do
      Enum.each(children_to_kill, &Process.exit(ctx.children[&1].pid, :kill))
      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_spec_started(_children, _ctx, state) do
      send(state.testing_pid, :spec_started)
      {:ok, state}
    end
  end

  setup do
    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        module: Pipeline,
        custom_args: %{testing_pid: self()}
      })

    on_exit(fn ->
      Membrane.Pipeline.stop_and_terminate(pipeline, blocking?: true)
    end)

    %{pipeline: pipeline}
  end

  test "element should crash when its neighbor connected via static pad crashes", %{
    pipeline: pipeline
  } do
    spec_1 = %Membrane.ParentSpec{
      children: [
        source: %Testing.Source{output: ['a', 'b', 'c']}
      ],
      crash_group: {:group_1, :temporary}
    }

    spec_2 = %Membrane.ParentSpec{
      children: [
        sink: Testing.Sink
      ],
      crash_group: {:group_2, :temporary}
    }

    links_spec = %Membrane.ParentSpec{
      links: [
        link(:source) |> to(:sink)
      ]
    }

    send(pipeline, {:start_spec, %{spec: spec_1}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec, %{spec: spec_2}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec_and_kill, %{spec: links_spec, children_to_kill: [:sink]}})
    assert_receive(:spec_started)

    assert_pipeline_crash_group_down(pipeline, :group_1)
    assert_pipeline_crash_group_down(pipeline, :group_2)
  end

  test "element shouldn't crash when its neighbor connected via dynamic pad crashes", %{
    pipeline: pipeline
  } do
    spec_1 = %Membrane.ParentSpec{
      children: [
        source: %DynamicSource{output: ['a', 'b', 'c']}
      ],
      crash_group: {:group_1, :temporary}
    }

    spec_2 = %Membrane.ParentSpec{
      children: [
        sink: Testing.Sink
      ],
      crash_group: {:group_2, :temporary}
    }

    links_spec = %Membrane.ParentSpec{
      links: [
        link(:source) |> to(:sink)
      ]
    }

    send(pipeline, {:start_spec, %{spec: spec_1}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec, %{spec: spec_2}})
    assert_receive(:spec_started)
    send(pipeline, {:start_spec_and_kill, %{spec: links_spec, children_to_kill: [:sink]}})
    assert_receive(:spec_started)

    refute_pipeline_crash_group_down(pipeline, :group_1)
    assert_pipeline_crash_group_down(pipeline, :group_2)
  end
end
