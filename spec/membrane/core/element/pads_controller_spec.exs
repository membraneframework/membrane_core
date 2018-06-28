defmodule Membrane.Core.Element.PadsControllerSpec do
  use ESpec, async: false
  alias Membrane.Support.Element.TrivialFilter
  alias Membrane.Core.Element.State

  describe ".link_pad/3" do
    let :module, do: TrivialFilter
    let :name, do: :element_name

    let! :state do
      {:ok, state} = State.new(module(), name()) |> described_module().init_pads()
      state
    end

    let :func, do: fn x -> MockModule.fake_function(x) end

    before do
      allow MockModule |> to(accept :fake_function, fn a -> a end)
    end

    context "when pad name is present in the element" do
      let :pad_name, do: :source
      let :direction, do: :source

      it "should return an ok result" do
        expect(described_module().link_pad(state(), pad_name(), direction(), func()))
        |> to(be_ok_result())
      end

      it "should call given function" do
        {:ok, _} = described_module().link_pad(state(), pad_name(), direction(), func())
        expect(MockModule |> to(accepted(:fake_function)))
      end

      it "should remove given pad from pads.info" do
        {:ok, new_state} = described_module().link_pad(state(), pad_name(), direction(), func())
        expect(new_state.pads.info[pad_name()]) |> to(eq nil)
      end

      it "should not modify state except pads list" do
        {:ok, new_state} = described_module().link_pad(state(), pad_name(), direction(), func())
        expect(%{new_state | pads: nil}) |> to(eq %{state() | pads: nil})
      end

      it "should add pad to the 'pads.data' list" do
        {:ok, new_state} = described_module().link_pad(state(), pad_name(), direction(), func())
        expect(described_module().get_pad_data(new_state, :any, pad_name())) |> to(be_ok_result())
      end
    end

    context "when pad name is not present in the element" do
      let :pad_name, do: :invalid_name
      let :direction, do: :source

      it "should return an error result" do
        expect(described_module().link_pad(state(), pad_name(), direction(), func()))
        |> to(be_error_result())
      end

      it "should not call given function" do
        described_module().link_pad(state(), pad_name(), direction(), func())
        expect(MockModule |> not_to(accepted(:fake_function)))
      end
    end
  end
end
