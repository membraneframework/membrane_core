defmodule Membrane.Core.PipelineTest do
  use ExUnit.Case

  @module Membrane.Core.Pipeline

  alias Membrane.Core.Pipeline.{ActionHandler, State}
  alias Membrane.ParentSpec
  alias Membrane.Testing

  defp state(_ctx) do
    [state: %State{module: nil, clock_proxy: nil}]
  end

  setup_all :state

  describe "Handle init" do
    test "should raise an error if handle_init returns an error" do
      defmodule ValidPipeline do
        use Membrane.Pipeline

        @impl true
        def handle_init(_options), do: {:error, :reason}
      end

      assert_raise Membrane.CallbackError, fn ->
        @module.init(ValidPipeline)
      end
    end

    test "executes successfully when callback module's handle_init returns {{:ok, spec: spec}}, state} " do
      defmodule InvalidPipeline do
        use Membrane.Pipeline

        @impl true
        def handle_init(_options) do
          spec = %Membrane.ParentSpec{}
          {{:ok, spec: spec}, %{}}
        end
      end

      assert {:ok, state} = @module.init(InvalidPipeline)

      assert %State{
               internal_state: %{},
               module: InvalidPipeline
             } = state
    end
  end

  describe "handle_action spec" do
    test "should raise if duplicate elements exist in spec", %{state: state} do
      assert_raise Membrane.ParentError, ~r/.*duplicate.*\[:a\]/i, fn ->
        ActionHandler.handle_action(
          {:spec, %ParentSpec{children: [a: :child1, a: :child2]}},
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
          {:spec, %ParentSpec{children: [a: :child]}},
          nil,
          [],
          state
        )
      end
    end
  end

  defmodule TestPipeline do
    use Membrane.Pipeline
  end

  test "Pipeline can be terminated synchronously" do
    {:ok, pid} = Testing.Pipeline.start_link(%Testing.Pipeline.Options{module: TestPipeline})

    assert :ok == Testing.Pipeline.stop_and_terminate(pid, blocking?: true)
  end
end
