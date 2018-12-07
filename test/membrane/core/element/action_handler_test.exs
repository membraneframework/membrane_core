defmodule Membrane.Core.Element.ActionHandlerTest do
  use ExUnit.Case, async: false
  alias Membrane.DemandTest.Filter
  alias Membrane.Core.{Element, Playback}
  alias Element.State

  @module Membrane.Core.Element.ActionHandler

  setup do
    state = %{
      State.new(Filter, :test_name)
      | watcher: self(),
        type: :filter,
        pads: %{
          data: %{
            input: %{
              direction: :input,
              pid: self(),
              mode: :pull,
              demand: 0
            },
            input_push: %{
              direction: :input,
              pid: self(),
              mode: :push
            }
          }
        }
    }

    [state: state]
  end

  describe "handling demand action" do
    test "delaying demand", %{state: state} do
      [{:playing, :handle_other}, {:prepared, :handle_prepared_to_playing}]
      |> Enum.each(fn {playback, callback} ->
        state = %{state | playback: %Playback{state: playback}}
        assert {:ok, state} = @module.handle_action({:demand, {:input, 10}}, callback, %{}, state)
        assert state.pads.data.input.demand == 10
        assert %{{:input, :supply} => :sync} == state.delayed_demands
      end)

      state = %{state | playback: %Playback{state: :playing}}

      assert {:ok, state} =
               @module.handle_action(
                 {:demand, {:input, 10}},
                 :handle_other,
                 %{supplying_demand?: true},
                 state
               )

      assert state.pads.data.input.demand == 10
      assert %{{:input, :supply} => :async} == state.delayed_demands
    end

    test "returning error on invalid constraints", %{state: state} do
      state = %{state | playback: %Playback{state: :prepared}}

      assert {{:error, {:cannot_handle_action, details}}, _state} =
               @module.handle_action({:demand, {:input, 10}}, :handle_other, %{}, state)

      assert {:cannot_supply_demand, _details} = details[:reason]

      state = %{state | playback: %Playback{state: :playing}}

      assert {{:error, {:cannot_handle_action, details}}, _state} =
               @module.handle_action({:demand, {:input_push, 10}}, :handle_other, %{}, state)

      assert {:invalid_pad_data, _details} = details[:reason]
    end
  end
end
