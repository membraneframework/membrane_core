defmodule Membrane.Core.Element.PadControllerTest do
  use ExUnit.Case, async: true

  alias Membrane.Core.Child.{PadModel, PadSpecHandler}
  alias Membrane.Core.Element.State
  alias Membrane.Core.Message
  alias Membrane.Core.SubprocessSupervisor
  alias Membrane.LinkError
  alias Membrane.Pad
  alias Membrane.Support.Element.{DynamicFilter, TrivialFilter}

  require Message
  require Pad

  @module Membrane.Core.Element.PadController

  defp prepare_state(elem_module, name \\ :element) do
    struct!(State,
      name: name,
      module: elem_module,
      # handling_action?: false,
      delay_demands?: false,
      pads_to_snapshot: MapSet.new(),
      delayed_demands: MapSet.new(),
      parent_pid: self(),
      internal_state: %{},
      synchronization: %{clock: nil, parent_clock: nil},
      subprocess_supervisor: SubprocessSupervisor.start_link!(),
      stalker: %Membrane.Core.Stalker{pid: spawn(fn -> :ok end), ets: nil},
      satisfied_auto_output_pads: MapSet.new(),
      awaiting_auto_input_pads: MapSet.new(),
      auto_input_pads: []
    )
    |> PadSpecHandler.init_pads()
  end

  describe ".handle_link" do
    test "when pad is present in the element" do
      state = prepare_state(TrivialFilter)

      assert {{:ok, _pad_info}, new_state} =
               @module.handle_link(
                 :input,
                 %{
                   pad_ref: :input,
                   pid: self(),
                   pad_props: %{min_demand_factor: 0.25, target_queue_size: 40, options: []},
                   child: :a
                 },
                 %{
                   pad_ref: :other_output,
                   pid: spawn(fn -> :ok end),
                   child: :b,
                   pad_props: %{options: [], toilet_capacity: nil, throttling_factor: nil}
                 },
                 %{
                   output_pad_info: %{
                     direction: :output,
                     flow_control: :manual,
                     demand_unit: :buffers
                   },
                   link_metadata: %{toilet: make_ref(), observability_data: %{path: ""}},
                   stream_format_validation_params: [],
                   output_effective_flow_control: :pull
                 },
                 state
               )

      assert Map.drop(new_state, [:pads_data, :pad_refs]) ==
               Map.drop(state, [:pads_data, :pad_refs])

      assert PadModel.assert_instance(new_state, :input) == :ok
    end

    test "when pad is does not exist in the element" do
      state = prepare_state(TrivialFilter)

      assert_raise LinkError, fn ->
        @module.handle_link(
          :output,
          %{pad_ref: :invalid_pad_ref, child: :a},
          %{pad_ref: :x, child: :b},
          %{stream_format_validation_params: []},
          state
        )
      end
    end
  end

  defp prepare_static_state(elem_module, name, pad_name) do
    {info, state} =
      elem_module
      |> prepare_state(name)
      |> pop_in([:pads_info, pad_name])

    data =
      struct(Membrane.Element.PadData,
        start_of_stream?: true,
        end_of_stream?: false
      )
      |> Map.merge(info)

    state
    |> put_in([:pads_data, pad_name], data)
  end

  defp prepare_dynamic_state(elem_module, name, pad_name, pad_ref) do
    state = elem_module |> prepare_state(name)
    info = state.pads_info[pad_name]

    data =
      struct(Membrane.Element.PadData,
        start_of_stream?: true,
        end_of_stream?: false
      )
      |> Map.merge(info)

    state |> put_in([:pads_data, pad_ref], data)
  end

  describe "handle_unlink" do
    test "for a static pad" do
      state = prepare_static_state(TrivialFilter, :element, :output)
      assert state.pads_data |> Map.has_key?(:output)

      assert_raise Membrane.PadError, fn ->
        @module.handle_unlink(:output, state)
      end
    end

    test "for dynamic input pad" do
      pad_ref = Pad.ref(:input, 0)
      state = prepare_dynamic_state(DynamicFilter, :element, :input, pad_ref)
      assert state.pads_data |> Map.has_key?(pad_ref)
      state = @module.handle_unlink(pad_ref, state)
      assert state.internal_state[:last_event] == nil
      assert state.internal_state.last_pad_removed == pad_ref
      refute state.pads_data |> Map.has_key?(pad_ref)
    end
  end
end
