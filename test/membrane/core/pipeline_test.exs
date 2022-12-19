defmodule Membrane.Core.PipelineTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.ChildrenSpec
  alias Membrane.Core.Message
  alias Membrane.Core.Pipeline.{ActionHandler, State}
  alias Membrane.Testing

  require Membrane.Core.Message

  @module Membrane.Core.Pipeline

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, result) do
      result || {[], %{}}
    end

    @impl true
    def handle_child_notification(notification, child, _ctx, state) do
      {[], Map.put(state, :child_notification, {notification, child})}
    end

    @impl true
    def handle_info(message, _ctx, state) do
      {[], Map.put(state, :other, message)}
    end
  end

  defmodule TestBin do
    use Membrane.Bin
  end

  defp state(_ctx) do
    subprocess_supervisor = Membrane.Core.SubprocessSupervisor.start_link!()
    parent_supervisor = Membrane.Core.SubprocessSupervisor.start_link!()

    [
      init_opts: %{
        name: :test_pipeline,
        module: TestPipeline,
        subprocess_supervisor: subprocess_supervisor,
        parent_supervisor: parent_supervisor,
        parent_path: [],
        log_metadata: [],
        options: nil
      },
      state:
        struct(State,
          module: TestPipeline,
          internal_state: %{},
          synchronization: %{clock_proxy: nil},
          subprocess_supervisor: subprocess_supervisor
        )
    ]
  end

  setup_all :state

  describe "Handle init" do
    test "executes successfully when callback module's handle_init returns {[spec: spec], state} ",
         %{init_opts: init_opts} do
      assert {:ok, state, {:continue, :setup}} = @module.init(%{init_opts | options: {[], %{}}})

      assert %State{internal_state: %{}, module: TestPipeline} = state
    end
  end

  describe "handle_action spec" do
    test "should raise if duplicate elements exist in spec", %{state: state} do
      assert_raise Membrane.ParentError, ~r/.*duplicate.*\[:a\]/i, fn ->
        ActionHandler.handle_action(
          {:spec, [child(:a, Membrane.Testing.Source) |> child(:a, Membrane.Testing.Sink)]},
          nil,
          [],
          state
        )
      end
    end

    test "should raise if trying to spawn element with already taken name", %{state: state} do
      state = %State{state | children: %{a: %{group: nil, name: :a}}}

      assert_raise Membrane.ParentError, ~r/.*duplicate.*\[:a\]/i, fn ->
        ActionHandler.handle_action(
          {:spec, [child(:a, TestBin)]},
          nil,
          [],
          state
        )
      end
    end
  end

  test "notification handling", %{state: state} do
    state = %State{state | children: %{source: %{}}}
    notification = Message.new(:child_notification, [:source, :abc])
    assert {:noreply, state} = @module.handle_info(notification, state)
    assert %{internal_state: %{child_notification: {:abc, :source}}} = state

    notification = Message.new(:child_notification, [:non_existent_child, :abc])

    assert_raise Membrane.UnknownChildError, fn ->
      @module.handle_info(notification, state)
    end
  end

  test "other messages handling", %{state: state} do
    state = %State{state | children: %{source: %{}}}
    assert {:noreply, state} = @module.handle_info(:other_message, state)
    assert %{internal_state: %{other: :other_message}} = state
  end

  test "Pipeline can be terminated synchronously" do
    pid = Testing.Pipeline.start_link_supervised!(module: TestPipeline)
    assert :ok == Testing.Pipeline.terminate(pid, blocking?: true)
  end

  test "Pipeline should be able to terminate itself with :terminate action" do
    Enum.each([:normal, :shutdown], fn reason ->
      {:ok, supervisor, pid} = Testing.Pipeline.start(module: TestPipeline)
      Process.monitor(supervisor)
      Testing.Pipeline.execute_actions(pid, terminate: reason)
      assert_receive {:DOWN, _ref, :process, ^supervisor, ^reason}
    end)
  end

  test "Pipeline should be able to spawn its children in a nested specification" do
    pid = Testing.Pipeline.start_link_supervised!(module: TestPipeline)
    opts1 = []
    opts2 = []

    spec = {
      [
        {child(:b, Testing.Sink), opts2},
        child(:a, %Testing.Source{output: [1, 2, 3]}) |> get_child(:b)
      ],
      opts1
    }

    Testing.Pipeline.execute_actions(pid, spec: spec)
    assert_pipeline_play(pid)
  end
end
