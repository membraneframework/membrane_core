defmodule Membrane.FilterAggregator.InternalActionTest do
  use ExUnit.Case, async: true

  require Membrane.Core.FilterAggregator.InternalAction, as: IA

  test "is_internal_action" do
    assert IA.is_internal_action(IA.stopped_to_prepared())
    assert IA.is_internal_action(IA.start_of_stream(:output))
  end

  test "Using macros as patterns" do
    pad = :output
    assert IA.start_of_stream(_ignored) = IA.start_of_stream(pad)
    assert IA.start_of_stream(^pad) = IA.start_of_stream(:output)
  end
end
