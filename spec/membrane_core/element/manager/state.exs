defmodule MockModule do
end

defmodule Membrane.Element.Manager.StateSpec do
  use ESpec, async: false
  alias Membrane.Support.Element.TrivialFilter

  describe ".new/2" do
    let :module, do: TrivialFilter
    let :name, do: :element_name

    it "should return an ok result" do
      expect(described_module().new(module(), name())) |> to(be_ok_result())
    end

    it "should return State struct" do
      {:ok, struct} = described_module().new(module(), name())
      expect(struct.__struct__) |> to(eq(described_module()))
    end

    it "should initialize empty playback buffer" do
      {:ok, struct} = described_module().new(module(), name())
      expect(struct.playback_buffer) |> to(eq(Membrane.Element.Manager.PlaybackBuffer.new()))
    end

    it "should return stopped playback state" do
      {:ok, struct} = described_module().new(module(), name())
      expect(struct.playback.state) |> to(eq(:stopped))
    end

    it "should return state containing element's name" do
      {:ok, struct} = described_module().new(module(), name())
      expect(struct.name) |> to(eq(name()))
    end

    it "should return state containing element's module" do
      {:ok, struct} = described_module().new(module(), name())
      expect(struct.module) |> to(eq(module()))
    end

    it "should initialize pads list" do
      {:ok, struct} = described_module().new(module(), name())
      expect(struct.pads) |> to(be_truthy())
    end

    pending("pads list should contain proper values")
  end

  describe ".link_pad/3" do
    let :module, do: TrivialFilter
    let :name, do: :element_name
    let! :state, do: described_module().new(module(), name()) |> elem(1)
    let :func, do: fn x -> MockModule.fake_function(x) end

    before do
      allow MockModule |> to(accept :fake_function, fn a -> a end)
    end

    context "when pad name is present in the element" do
      let :pad_name, do: :source

      it "should return an ok result" do
        expect(described_module().link_pad(state(), pad_name(), func())) |> to(be_ok_result())
      end

      it "should call given function" do
        {:ok, _} = described_module().link_pad(state(), pad_name(), func())
        expect(MockModule |> to(accepted(:fake_function)))
      end

      it "should remove given pad from pads.info" do
        {:ok, new_state} = described_module().link_pad(state(), pad_name(), func())
        expect(new_state.pads.info[pad_name()]) |> to(eq(nil))
      end

      it "should not modify state except pads list" do
        {:ok, new_state} = described_module().link_pad(state(), pad_name(), func())
        expect(%{new_state | pads: nil}) |> to(eq(%{state() | pads: nil}))
      end

      it "should add pad to the 'pads.data' list" do
        {:ok, new_state} = described_module().link_pad(state(), pad_name(), func())
        expect(described_module.get_pad_data(new_state, :any, pad_name())) |> to(be_ok_result())
      end
    end

    context "when pad name is not present in the element" do
      let :pad_name, do: :invalid_name

      it "should return an error result" do
        expect(described_module().link_pad(state(), pad_name(), func())) |> to(be_error_result())
      end

      it "should not call given function" do
        described_module().link_pad(state(), pad_name(), func())
        expect(MockModule |> not_to(accepted(:fake_function)))
      end
    end
  end
end
