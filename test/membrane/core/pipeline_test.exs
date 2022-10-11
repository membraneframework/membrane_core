defmodule Membrane.Core.PipelineTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  alias Membrane.ChildrenSpec
  alias Membrane.Core.Message
  alias Membrane.Core.Pipeline.{ActionHandler, State}
  alias Membrane.Testing

  require Membrane.Core.Message

  @module Membrane.Core.Pipeline

  defmodule TestPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(result) do
      result || {:ok, %{}}
    end

    @impl true
    def handle_child_notification(notification, child, _ctx, state) do
      {:ok, Map.put(state, :child_notification, {notification, child})}
    end

    @impl true
    def handle_info(message, _ctx, state) do
      {:ok, Map.put(state, :other, message)}
    end
  end

  defp state(_ctx) do
    children_supervisor = Membrane.Core.ChildrenSupervisor.start_link!()

    [
      init_opts: %{
        name: :test_pipeline,
        module: TestPipeline,
        children_supervisor: children_supervisor,
        parent_path: [],
        log_metadata: [],
        options: nil
      },
      state:
        struct(State,
          module: TestPipeline,
          internal_state: %{},
          synchronization: %{clock_proxy: nil},
          children_supervisor: children_supervisor
        )
    ]
  end

  setup_all :state

  describe "Handle init" do
    test "should raise an error if handle_init returns an error", %{init_opts: init_opts} do
      assert_raise Membrane.CallbackError, fn ->
        @module.init(%{init_opts | options: {:error, :reason}})
      end
    end

    test "executes successfully when callback module's handle_init returns {{:ok, spec: spec}}, state} ",
         %{init_opts: init_opts} do
      assert {:ok, state, {:continue, :setup}} =
               @module.init(%{init_opts | options: {{:ok, spec: %Membrane.ChildrenSpec{}}, %{}}})

      assert %State{internal_state: %{}, module: TestPipeline} = state
    end
  end

  describe "handle_action spec" do
    test "should raise if duplicate elements exist in spec", %{state: state} do
      assert_raise Membrane.ParentError, ~r/.*duplicate.*\[:a\]/i, fn ->
        ActionHandler.handle_action(
          {:spec,
           %ChildrenSpec{structure: [a: Membrane.Testing.Source, a: Membrane.Testing.Sink]}},
          nil,
          [],
          state
        )
      end
    end

    test "should raise if trying to spawn element with already taken name", %{state: state} do
      state = %State{state | children: %{a: self()}}

      assert_raise Membrane.ParentError, ~r/.*duplicate.*\[:a\]/i, fn ->
        ActionHandler.handle_action(
          {:spec, %ChildrenSpec{structure: [a: Membrane.Testing.Source]}},
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

  test "Pipeline should be able to steer its playback with :playback action" do
    pid = Testing.Pipeline.start_link_supervised!(module: TestPipeline)
    Testing.Pipeline.execute_actions(pid, playback: :playing)
    assert_pipeline_play(pid)
  end

  test "Pipeline should be able to terminate itself with :terminate action" do
    Enum.each([:normal, :shutdown], fn reason ->
      {:ok, supervisor, pid} = Testing.Pipeline.start(module: TestPipeline)
      Process.monitor(supervisor)
      Testing.Pipeline.execute_actions(pid, terminate: reason)
      assert_receive {:DOWN, _ref, :process, ^supervisor, ^reason}
    end)
  end
end
