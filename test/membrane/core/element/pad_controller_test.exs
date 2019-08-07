defmodule Membrane.Core.PadControllerTest do
  use ExUnit.Case, async: true
  alias Membrane.Support.Element.{DynamicFilter, TrivialFilter, TrivialSink}
  alias Membrane.Core.Element.{PadModel, State}
  alias Membrane.Core.{Message, Playbackable}
  alias Membrane.LinkError
  alias Membrane.Event.EndOfStream
  require Message

  @module Membrane.Core.PadController

  defp prepare_state(elem_module, name \\ :element, playback_state \\ :stopped) do
    elem_module
    |> State.new(name)
    |> Playbackable.update_playback(&%{&1 | state: playback_state})
    |> PadSpecHandler.init_pads()
    |> Bunch.Access.put_in(:internal_state, %{})
    |> Bunch.Access.put_in(:watcher, self())
  end

  describe ".handle_link/7" do
    test "when pad is present in the element" do
      state = prepare_state(TrivialFilter)

      assert {{:ok, pad_info}, new_state} =
               @module.handle_link(
                 :output,
                 :output,
                 self(),
                 :other_input,
                 nil,
                 %{},
                 state
               )

      assert %{new_state | pads: nil} == %{state | pads: nil}
      refute new_state.pads.info |> Map.has_key?(:output)
      assert PadModel.assert_instance(new_state, :output) == :ok
    end

    test "when pad is does not exist in the element" do
      state = prepare_state(TrivialFilter)

      assert_raise LinkError, fn ->
        @module.handle_link(
          :invalid_pad_ref,
          :output,
          self(),
          :other_input,
          nil,
          %{},
          state
        )
      end
    end
  end

  describe "get_pad_ref/3" do
    test "on a static pad" do
      state = prepare_state(TrivialFilter)
      assert @module.get_pad_ref(:input, nil, state) == {{:ok, :input}, state}
      assert @module.get_pad_ref(:input, 1, state) == {{:error, :id_on_static_pad}, state}
    end

    test "without supplied id on a dynamic pad" do
      state = prepare_state(DynamicFilter)
      assert {{:ok, {:dynamic, :input, 0}}, new_state} = @module.get_pad_ref(:input, nil, state)
      assert new_state.pads.info.input.current_id == 1
      assert {{:ok, {:dynamic, :input, 1}}, _state} = @module.get_pad_ref(:input, nil, new_state)
    end

    test "with supplied id on a dynamic pad" do
      state = prepare_state(DynamicFilter)
      assert {{:ok, {:dynamic, :input, 666}}, new_state} = @module.get_pad_ref(:input, 666, state)
      assert new_state.pads.info.input.current_id == 667

      assert {{:ok, {:dynamic, :input, 667}}, _} = @module.get_pad_ref(:input, 667, new_state)
    end
  end

  defp prepare_static_state(elem_module, name \\ :element, pad_name) do
    {info, state} =
      elem_module
      |> prepare_state(name)
      |> Bunch.Access.pop_in([:pads, :info, pad_name])

    data =
      %Pad.Data{
        start_of_stream?: true,
        end_of_stream?: false
      }
      |> Map.merge(info)

    state |> Bunch.Access.put_in([:pads, :data, pad_name], data)
  end

  defp prepare_dynamic_state(elem_module, name, playback_state, pad_name, pad_ref) do
    state = elem_module |> prepare_state(name, playback_state)
    info = state.pads.info[pad_name]

    data =
      %Pad.Data{
        start_of_stream?: true,
        end_of_stream?: false
      }
      |> Map.merge(info)

    state |> Bunch.Access.put_in([:pads, :data, pad_ref], data)
  end

  describe "handle_unlink" do
    test "for static output pad" do
      state = prepare_static_state(TrivialFilter, :output)
      assert state.pads.data |> Map.has_key?(:output)
      assert {:ok, new_state} = @module.handle_unlink(:output, state)
      refute new_state.pads.data |> Map.has_key?(:output)
    end

    test "for static input pad" do
      state = prepare_static_state(TrivialSink, :input)
      assert state.pads.data |> Map.has_key?(:input)
      assert {:ok, new_state} = @module.handle_unlink(:input, state)
      assert_received Message.new(:handle_end_of_stream, [:element, :input])
      refute new_state.pads.data |> Map.has_key?(:input)
    end

    test "for dynamic input pad" do
      pad_ref = {:dynamic, :input, 0}
      state = prepare_dynamic_state(DynamicFilter, :element, :playing, :input, pad_ref)
      assert state.pads.data |> Map.has_key?(pad_ref)
      assert {:ok, new_state} = @module.handle_unlink(pad_ref, state)
      assert new_state.internal_state[:last_event] == nil
      assert new_state.internal_state.last_pad_removed == pad_ref
      refute new_state.pads.data |> Map.has_key?(pad_ref)
    end
  end
end
