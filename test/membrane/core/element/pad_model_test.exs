defmodule Membrane.Core.Child.PadModelTest do
  use ExUnit.Case, async: true

  require Membrane.Core.Child.PadModel, as: PadModel

  @unknown_pad_error_module if Version.match?(System.version(), ">= 1.14.0-dev"),
                              do: Membrane.UnknownPadError,
                              else: MatchError

  defp setup_element_state(_ctx) do
    state = %Membrane.Core.Element.State{
      pads_data: %{:input => struct(Membrane.Element.PadData, demand_snapshot: 1)},
      pads_info: %{}
    }

    [state: state]
  end

  describe "assert_instance" do
    setup :setup_element_state

    test "is :ok when the pad is present", ctx do
      assert PadModel.assert_instance(ctx.state, :input) == :ok
    end

    test "is :unknown_pad when the pad is not present", ctx do
      assert PadModel.assert_instance(ctx.state, :output) == {:error, :unknown_pad}
    end
  end

  describe "get_data" do
    setup :setup_element_state

    test "is {:ok, value} when the pad is present", ctx do
      assert {:ok, 1} = PadModel.get_data(ctx.state, :input, :demand_snapshot)
    end

    test "is :unknown_pad when the pad is not present", ctx do
      assert PadModel.get_data(ctx.state, :output, :demand_snapshot) ==
               {:error, :unknown_pad}
    end
  end

  describe "get_data!" do
    setup :setup_element_state

    test "is value when the pad is present", ctx do
      assert 1 = PadModel.get_data!(ctx.state, :input, :demand_snapshot)
    end

    test "is :unknown_pad when the pad is not present", ctx do
      assert_raise @unknown_pad_error_module, fn ->
        PadModel.get_data!(ctx.state, :output, :demand_snapshot)
      end
    end
  end

  describe "set_data" do
    setup :setup_element_state

    test "is {:ok, state} when the pad is present", ctx do
      assert get_in(ctx.state, [:pads_data, :input, :start_of_stream?]) == false
      assert {:ok, state} = PadModel.set_data(ctx.state, :input, :start_of_stream?, true)
      assert get_in(state, [:pads_data, :input, :start_of_stream?]) == true
    end

    test "is :unknown_pad when the pad is not present", ctx do
      assert PadModel.set_data(ctx.state, :output, :start_of_stream?, true) ==
               {{:error, :unknown_pad}, ctx.state}
    end
  end

  describe "set_data!" do
    setup :setup_element_state

    test "updates the pad data with the given function when present", ctx do
      assert get_in(ctx.state, [:pads_data, :input, :start_of_stream?]) == false
      assert state = PadModel.set_data!(ctx.state, :input, :start_of_stream?, true)
      assert get_in(state, [:pads_data, :input, :start_of_stream?]) == true
    end

    test "raises when the pad is not present", ctx do
      assert_raise @unknown_pad_error_module, fn ->
        PadModel.set_data!(ctx.state, :other_input, :start_of_stream?, true)
      end
    end
  end

  describe "update_data" do
    setup :setup_element_state

    test "updates the pad data with the given function when present", ctx do
      assert PadModel.update_data(ctx.state, :input, :demand_snapshot, &{:ok, &1 + 5}) ==
               {:ok, put_in(ctx.state, [:pads_data, :input, :demand_snapshot], 6)}
    end

    test "is :unknown_pad and original state when the pad is not present", ctx do
      assert PadModel.update_data(ctx.state, :output, :demand_snapshot, &{:ok, &1 + 1}) ==
               {{:error, :unknown_pad}, ctx.state}
    end
  end

  describe "update_data!" do
    setup :setup_element_state

    test "updates the pad data with the given function when present", ctx do
      assert PadModel.update_data!(ctx.state, :input, :demand_snapshot, &(&1 + 5)) ==
               put_in(ctx.state, [:pads_data, :input, :demand_snapshot], 6)
    end

    test "raises when the pad is not present", ctx do
      assert_raise @unknown_pad_error_module, fn ->
        PadModel.update_data!(ctx.state, :other_input, :demand_snapshot, &(&1 + 5))
      end
    end
  end
end
