defmodule Membrane.PipelineTest do
  @module Membrane.Pipeline

  alias Membrane.Pipeline.{Spec, State}
  use ExUnit.Case

  def state(_ctx) do
    [state: %State{}]
  end

  setup_all :state

  describe "handle_action spec" do
    test "should raise if duplicate elements exist in spec", %{state: state} do
      assert_raise Membrane.ParentError, ~r/.*duplicate.*\[:a\]/i, fn ->
        @module.handle_action(
          {:spec, %Spec{children: [a: :child1, a: :child2]}},
          nil,
          [],
          state
        )
      end
    end

    test "should raise if trying to spawn element with already taken name", %{state: state} do
      state = %State{state | children: %{a: self()}}

      assert_raise Membrane.ParentError, ~r/.*duplicate.*\[:a\]/i, fn ->
        @module.handle_action(
          {:spec, %Spec{children: [a: :child]}},
          nil,
          [],
          state
        )
      end
    end
  end
end
