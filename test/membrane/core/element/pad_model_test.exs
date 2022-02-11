defmodule Membrane.Core.Child.PadModelTest do
  use ExUnit.Case, async: true

  alias Membrane.Core.Child.PadModel

  defp setup_element_state(_ctx) do
    state = %Membrane.Core.Element.State{
      pads: %{
        data: %{:input => struct(Membrane.Element.PadData, demand: 1)},
        info: %{},
        dynamic_currently_linking: []
      }
    }

    [state: state]
  end

  describe "assert_instance" do
    setup :setup_element_state

    test "is :ok when the pad is present", ctx do
      assert PadModel.assert_instance(ctx.state, :input) == :ok
    end

    test "is :unknown_pad when the pad is not present", ctx do
      assert PadModel.assert_instance(ctx.state, :output) == {:error, {:unknown_pad, :output}}
    end
  end

  describe "get_data" do
    setup :setup_element_state

    test "is {:ok, value} when the pad is present", ctx do
      assert {:ok, 1} = PadModel.get_data(ctx.state, :input, :demand)
    end

    test "is :unknown_pad when the pad is not present", ctx do
      assert PadModel.get_data(ctx.state, :output, :demand) ==
               {:error, {:unknown_pad, :output}}
    end
  end

  describe "get_data!" do
    setup :setup_element_state

    test "is value when the pad is present", ctx do
      assert 1 = PadModel.get_data!(ctx.state, :input, :demand)
    end

    test "is :unknown_pad when the pad is not present", ctx do
      assert_raise MatchError, fn ->
        PadModel.get_data!(ctx.state, :output, :demand)
      end
    end
  end

  describe "set_data" do
    setup :setup_element_state

    test "is {:ok, state} when the pad is present", ctx do
      assert ctx.state.pads.data.input.start_of_stream? == false
      assert {:ok, state} = PadModel.set_data(ctx.state, :input, :start_of_stream?, true)
      assert state.pads.data.input.start_of_stream? == true
    end

    test "is :unknown_pad when the pad is not present", ctx do
      assert PadModel.set_data(ctx.state, :output, :start_of_stream?, true) ==
               {{:error, {:unknown_pad, :output}}, ctx.state}
    end
  end

  describe "set_data!" do
    setup :setup_element_state

    test "updates the pad data with the given function when present", ctx do
      assert ctx.state.pads.data.input.start_of_stream? == false
      assert state = PadModel.set_data!(ctx.state, :input, :start_of_stream?, true)
      assert state.pads.data.input.start_of_stream? == true
    end

    test "raises when the pad is not present", ctx do
      assert_raise MatchError, fn ->
        PadModel.set_data!(ctx.state, :other_input, :start_of_stream?, true)
      end
    end
  end

  describe "update_data" do
    setup :setup_element_state

    test "updates the pad data with the given function when present", ctx do
      assert PadModel.update_data(ctx.state, :input, :demand, &{:ok, &1 + 5}) ==
               {:ok, put_in(ctx.state, [:pads, :data, :input, :demand], 6)}
    end

    test "is :unknown_pad and original state when the pad is not present", ctx do
      assert PadModel.update_data(ctx.state, :output, :demand, &{:ok, &1 + 1}) ==
               {{:error, {:unknown_pad, :output}}, ctx.state}
    end
  end

  describe "update_data!" do
    setup :setup_element_state

    test "updates the pad data with the given function when present", ctx do
      assert PadModel.update_data!(ctx.state, :input, :demand, &(&1 + 5)) ==
               put_in(ctx.state, [:pads, :data, :input, :demand], 6)
    end

    test "raises when the pad is not present", ctx do
      assert_raise MatchError, fn ->
        PadModel.update_data!(ctx.state, :other_input, :demand, &(&1 + 5))
      end
    end
  end

  describe "update_multi" do
    setup :setup_element_state

    test "updates multiple values in a pad", ctx do
      assert %{demand: 1, start_of_stream?: false} = Map.get(ctx.state.pads.data, :input)

      assert {:ok, state} =
               PadModel.update_multi(ctx.state, :input, [
                 {:demand, &(&1 + 44)},
                 {:start_of_stream?, true}
               ])

      assert %{demand: 45, start_of_stream?: true} = Map.get(state.pads.data, :input)
    end

    test "is :unknown_pad and original state when the pad is not present", ctx do
      assert PadModel.update_multi(ctx.state, :other_input, [
               {:demand, &(&1 + 44)},
               {:start_of_stream?, true}
             ]) ==
               {{:error, {:unknown_pad, :other_input}}, ctx.state}
    end
  end

  describe "update_multi!" do
    setup :setup_element_state

    test "updates multiple values in a pad", ctx do
      assert %{demand: 1, start_of_stream?: false} = Map.get(ctx.state.pads.data, :input)

      assert state =
               PadModel.update_multi!(ctx.state, :input, [
                 {:demand, &(&1 + 44)},
                 {:start_of_stream?, true}
               ])

      assert %{demand: 45, start_of_stream?: true} = Map.get(state.pads.data, :input)
    end

    test "is :unknown_pad and original state when the pad is not present", ctx do
      assert_raise MatchError, fn ->
        PadModel.update_multi!(ctx.state, :other_input, [
          {:demand, &(&1 + 44)},
          {:start_of_stream?, true}
        ])
      end
    end
  end
end
