defmodule Membrane.Core.Element.PadControllerSpec do
  use ESpec, async: false
  alias Membrane.Support.Element.TrivialFilter
  alias Membrane.Core.Element.{PadModel, PadSpecHandler, State}

  describe ".link_pad/3" do
    let :module, do: TrivialFilter
    let :name, do: :element_name

    let! :state do
      State.new(module(), name()) |> PadSpecHandler.init_pads()
    end

    context "when pad is present in the element" do
      let :pad_ref, do: :out
      let :pad_name, do: :out
      let :direction, do: :output
      let :other_ref, do: :other_in
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
      let :other_ref, do: :other_in
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
end
