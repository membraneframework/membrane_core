defmodule Membrane.Device.AudioEnumeratorSpec do
  use ESpec, async: true

  alias Membrane.Device.AudioDevice

  describe ".diff_list/2" do
    context "if both lists are empty" do
      let :list1, do: []
      let :list2, do: []

      it "should return tuple with three empty lists" do
        expect(described_module().diff_list(list1(), list2())).to eq {[], [], []}
      end
    end

    context "if first list is empty but second list is not empty" do
      let :device, do: %AudioDevice{id: "123", driver: :test, name: "x", direction: :capture}
      let :list1, do: []
      let :list2, do: [device()]

      it "should return tuple with added device present in the first list and two empty lists" do
        expect(described_module().diff_list(list1(), list2())).to eq {[device()], [], []}
      end
    end

    context "if first list is not empty but second list is empty" do
      let :device, do: %AudioDevice{id: "123", driver: :test, name: "x", direction: :capture}
      let :list1, do: [device()]
      let :list2, do: []

      it "should return tuple with removed device present in the second list and two empty lists" do
        expect(described_module().diff_list(list1(), list2())).to eq {[], [device()], []}
      end
    end

    context "if both lists are equal" do
      let :device, do: %AudioDevice{id: "123", driver: :test, name: "x", direction: :capture}
      let :list1, do: [device()]
      let :list2, do: [device()]

      it "should return tuple with unchanged device present in the third list and two empty lists" do
        expect(described_module().diff_list(list1(), list2())).to eq {[], [], [device()]}
      end
    end

    context "if both lists are partially different" do
      let :device1, do: %AudioDevice{id: "123", driver: :test, name: "x", direction: :capture}
      let :device2, do: %AudioDevice{id: "456", driver: :test, name: "x", direction: :capture}
      let :device3, do: %AudioDevice{id: "789", driver: :test, name: "x", direction: :capture}
      let :list1, do: [device1(), device2()]
      let :list2, do: [device2(), device3()]

      it "should return tuple with added, removed and unchaged devices" do
        expect(described_module().diff_list(list1(), list2())).to eq {[device3()], [device1()], [device2()]}
      end
    end
  end
end
