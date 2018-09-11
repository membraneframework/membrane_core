defmodule Membrane.PipelineTest do
  @module Membrane.Pipeline

  alias Membrane.Pipeline.{Spec, State}
  use ExUnit.Case

  def state(_ctx) do
    [state: %State{}]
  end

  setup_all :state

  describe "handle_action spec" do
    test "should return error if duplicate elements exist in spec", %{state: state} do
      assert {{:error, {:cannot_handle_spec, {:duplicate_element_names, [:a]}}}, _state} =
               @module.handle_action(
                 {:spec, %Spec{children: [a: :child1, a: :child2]}},
                 nil,
                 [],
                 state
               )
    end

    test "should return error if trying to spawn element with already taken name", %{state: state} do
      state = %State{state | children: %{a: self()}}

      assert {{:error, {:cannot_handle_spec, {:duplicate_element_names, [:a]}}}, _state} =
               @module.handle_action(
                 {:spec, %Spec{children: [a: :child]}},
                 nil,
                 [],
                 state
               )
    end
  end
end
