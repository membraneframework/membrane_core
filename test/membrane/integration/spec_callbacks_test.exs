defmodule Membrane.SpecCallbacksTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec

  alias Membrane.Testing

  defmodule Pipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, opts), do: {[], Map.new(opts)}

    @impl true
    def handle_setup(_ctx, state) do
      case state do
        %{delay_setup?: true} -> {[setup: :incomplete], state}
        state -> {[], state}
      end
    end

    @impl true
    def handle_child_setup_completed(child, _ctx, state) do
      send(state.test_pid, {:setup_completed, child})
      {[], state}
    end

    @impl true
    def handle_child_playing(child, _ctx, state) do
      send(state.test_pid, {:playing, child})
      {[], state}
    end
  end

  defmodule Element do
    use Membrane.Endpoint

    def_options delay_setup?: [default: false]

    @impl true
    def handle_init(_ctx, opts), do: {[], Map.from_struct(opts)}

    @impl true
    def handle_setup(_ctx, state) do
      if state.delay_setup?,
        do: {[setup: :incomplete], state},
        else: {[], state}
    end

    @impl true
    def handle_parent_notification(:complete_setup, _ctx, state) do
      {[setup: :complete], state}
    end
  end

  defp pipeline_spec_actions() do
    [
      spec: child(:a, Element),
      spec: child(:b, %Element{delay_setup?: true}),
      spec: [child(:c, Element), child(:d, %Element{delay_setup?: true})],
      spec: child(:e, %Element{delay_setup?: true})
    ]
  end

  test "handle_child_setup_completed and handle_child_playing when a child completes setup after parent" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        module: Pipeline,
        custom_args: [test_pid: self()]
      )

    Testing.Pipeline.execute_actions(pipeline, pipeline_spec_actions())

    assert_receive {:setup_completed, :a}
    assert_receive {:playing, :a}
    refute_receive {:setup_completed, _any}
    refute_receive {:playing, _any}

    Testing.Pipeline.notify_child(pipeline, :b, :complete_setup)

    assert_receive {:setup_completed, :b}
    assert_receive {:playing, :b}
    refute_receive {:setup_completed, _any}
    refute_receive {:playing, _any}

    Testing.Pipeline.notify_child(pipeline, :d, :complete_setup)

    assert_receive {:setup_completed, :c}
    assert_receive {:setup_completed, :d}
    assert_receive {:playing, :c}
    assert_receive {:playing, :d}

    refute_receive {:setup_completed, _any}
    refute_receive {:playing, _any}

    :ok = Testing.Pipeline.terminate(pipeline)
  end

  test "handle_child_setup_completed and handle_child_playing when a child completes setup before parent" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        module: Pipeline,
        custom_args: [test_pid: self(), delay_setup?: true]
      )

    Testing.Pipeline.execute_actions(pipeline, pipeline_spec_actions())

    assert_receive {:setup_completed, :a}
    refute_receive {:setup_completed, _any}
    refute_receive {:playing, _any}

    Testing.Pipeline.notify_child(pipeline, :b, :complete_setup)

    assert_receive {:setup_completed, :b}
    refute_receive {:setup_completed, _any}
    refute_receive {:playing, _any}

    Testing.Pipeline.notify_child(pipeline, :d, :complete_setup)

    assert_receive {:setup_completed, :c}
    assert_receive {:setup_completed, :d}
    refute_receive {:setup_completed, _any}
    refute_receive {:playing, _any}

    Testing.Pipeline.execute_actions(pipeline, setup: :complete)

    for child <- [:a, :b, :c, :d] do
      assert_receive {:playing, ^child}
    end

    refute_receive {:setup_completed, _any}
    refute_receive {:playing, _any}

    :ok = Testing.Pipeline.terminate(pipeline)
  end
end
