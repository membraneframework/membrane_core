defmodule Membrane.Core.Element.ActionHandlerTest do
  use ExUnit.Case, async: false
  alias Membrane.Integration.TestingFilter
  alias Membrane.Core.{Element, Playback}
  alias Element.State

  @module Membrane.Core.Element.ActionHandler

  setup do
    state = %{
      State.new(TestingFilter, :test_name)
      | message_bus: self(),
        type: :filter,
        pads: %{
          data: %{
            input: %{
              direction: :input,
              pid: self(),
              mode: :pull,
              demand: 0
            }
          }
        }
    }

    [state: state]
  end

  describe "demand action" do
    test "demand should be supplied when proper state conditions are met", %{state: state} do
      [{:playing, :handle_other}, {:prepared, :handle_prepared_to_playing}]
      |> Enum.each(fn {playback, callback} ->
        state = %{state | playback: %Playback{state: playback}}
        assert {:ok, state} = @module.handle_action({:demand, {:input, 10}}, callback, %{}, state)
        assert state.pads.data.input.demand == 10
        assert %{{:input, :supply} => :sync} == state.delayed_demands
      end)

      state = %{state | playback: %Playback{state: :prepared}}

      assert {{:error, {:cannot_handle_action, details}}, _state} =
               @module.handle_action({:demand, {:input, 10}}, :handle_other, %{}, state)

      assert {:cannot_supply_demand, _details} = details[:reason]
    end
  end
end
