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

    context "when pad name is present in the element" do
      let :pad_name, do: :source
      let :direction, do: :source
      let :other_ref, do: :other_sink
      let :props, do: %{}

      it "should return an ok result" do
        expect(
          described_module().handle_link(
            pad_name(),
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
            pad_name(),
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
            pad_name(),
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
            pad_name(),
            direction(),
            self(),
            other_ref(),
            props(),
            state()
          )

        expect(PadModel.assert_instance(pad_name(), new_state)) |> to(eq :ok)
      end
    end

    context "when pad name is not present in the element" do
      let :pad_name, do: :invalid_name
      let :direction, do: :source
      let :other_ref, do: :other_sink
      let :props, do: %{}

      it "should return an error result" do
        {result, _state} =
          described_module().handle_link(
            pad_name(),
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
