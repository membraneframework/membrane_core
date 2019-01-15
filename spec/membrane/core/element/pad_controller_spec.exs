defmodule Membrane.Core.Element.PadControllerSpec do
  use ESpec, async: false
  alias Membrane.Support.Element.{DynamicFilter, TrivialFilter}
  alias Membrane.Core.Element.{PadModel, PadSpecHandler, State}

  describe ".link_pad/6" do
    let :module, do: TrivialFilter
    let :name, do: :element_name

    let! :state do
      State.new(module(), name()) |> PadSpecHandler.init_pads()
    end

    context "when pad is present in the element" do
      let :pad_ref, do: :output
      let :pad_name, do: :output
      let :direction, do: :output
      let :other_ref, do: :other_input
      let :props, do: %{}

      it "should return an ok result" do
        expect(
          described_module().handle_link(
            pad_ref(),
            direction(),
            self(),
            other_ref(),
            props(),
            state()
          )
        )
        |> to(be_ok_result())
      end

      it "should remove given pad from pads.info" do
        {:ok, new_state} =
          described_module().handle_link(
            pad_ref(),
            direction(),
            self(),
            other_ref(),
            props(),
            state()
          )

        expect(new_state.pads.info |> Map.has_key?(pad_name())) |> to(eq false)
      end

      it "should not modify state except pads list" do
        {:ok, new_state} =
          described_module().handle_link(
            pad_ref(),
            direction(),
            self(),
            other_ref(),
            props(),
            state()
          )

        expect(%{new_state | pads: nil}) |> to(eq %{state() | pads: nil})
      end

      it "should add pad to the 'pads.data' list" do
        {:ok, new_state} =
          described_module().handle_link(
            pad_ref(),
            direction(),
            self(),
            other_ref(),
            props(),
            state()
          )

        expect(PadModel.assert_instance(pad_ref(), new_state)) |> to(eq :ok)
      end
    end

    context "when pad is not present in the element" do
      let :pad_ref, do: :invalid_ref
      let :direction, do: :output
      let :other_ref, do: :other_input
      let :props, do: %{}

      it "should return an error result" do
        {result, _state} =
          described_module().handle_link(
            pad_ref(),
            direction(),
            self(),
            other_ref(),
            props(),
            state()
          )

        expect(result) |> to(be_error_result())
      end
    end
  end

  describe "handle_unlink" do
    let :name, do: :element_name
    let :other_ref, do: :other_pad

    let :pad_data,
      do: %Membrane.Element.Pad.Data{
        start_of_stream?: true,
        end_of_stream?: false
      }

    let! :state do
      {pad_info, state} =
        State.new(module(), name())
        |> PadSpecHandler.init_pads()
        |> Bunch.Access.get_and_update_in(
          [:pads, :info],
          &{&1 |> Map.get(pad_name()), &1 |> Map.delete(pad_name())}
        )

      data = pad_data() |> Map.merge(pad_info)
      state |> Bunch.Access.update_in([:pads, :data], &(&1 |> Map.put(pad_ref(), data)))
    end

    context "for element with static output pad" do
      let :module, do: TrivialFilter
      let :pad_name, do: :output
      let :pad_ref, do: pad_name()
      let :direction, do: :output

      it "should unlink that pad" do
        {result, _state} =
          described_module().handle_unlink(
            pad_ref(),
            state()
          )

        expect(result) |> to(eq :ok)
      end
    end

    context "for element with static input pad" do
      let :module, do: TrivialFilter
      let :pad_name, do: :input
      let :pad_ref, do: pad_name()
      let :direction, do: :input

      it "should unlink that pad and set end_of_stream" do
        {result, state} =
          described_module().handle_unlink(
            pad_ref(),
            state()
          )

        expect(result) |> to(eq :ok)
        expect(state.pads.data[pad_ref()].end_of_stream?) |> to(be_true())
      end
    end

    context "for element with dynamic input pad" do
      let :module, do: DynamicFilter
      let :pad_name, do: :input
      let :pad_ref, do: {:input, 0}

      let :pad_data,
        do: %Membrane.Element.Pad.Data{
          start_of_stream?: true,
          end_of_stream?: false
        }

      let :direction, do: :input

      it "should unlink that pad, send end_of_stream and delete pad" do
        {result, state} =
          described_module().handle_unlink(
            pad_ref(),
            state()
          )

        expect(result) |> to(eq :ok)
        expect(state.pads.data[pad_ref()]) |> to(be_nil())
        ref = pad_ref()
        assert_received {:pad_removed, ^ref}
      end
    end
  end
end
