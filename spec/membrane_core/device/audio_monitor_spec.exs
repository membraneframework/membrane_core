defmodule Membrane.Device.AudioMonitorSpec do
  use ESpec, async: true
  alias Membrane.Support.Device.FakeAudioEnumerator
  alias Membrane.Support.Device.TrivialAudioMonitor

  pending ".start_link/4"
  pending ".start/4"
  pending ".stop/2"

  describe ".get_devices/3" do
    let :timeout, do: 5000
    let :enumerator, do: FakeAudioEnumerator

    let_ok :server, do: described_module().start(TrivialAudioMonitor, [enumerator()])
    finally do: Process.exit(server(), :kill)

    context "if passed query is :all" do
      let :query, do: :all

      it "should return all devices returned by the underlying enumerator for the same query regardless of its order" do
        # We are using MapSet to compare because order does not matter
        returned_devices = described_module().get_devices(server(), query(), timeout()) |> MapSet.new
        {:ok, expected_devices} = enumerator().list(query())
        expected_devices = expected_devices |> MapSet.new
        expect(MapSet.equal?(returned_devices, expected_devices)).to be_true()
      end
    end

    context "if passed query is :capture" do
      let :query, do: :capture

      it "should return all devices returned by the underlying enumerator for the same query regardless of its order" do
        # We are using MapSet to compare because order does not matter
        returned_devices = described_module().get_devices(server(), query(), timeout()) |> MapSet.new
        {:ok, expected_devices} = enumerator().list(query())
        expected_devices = expected_devices |> MapSet.new
        expect(MapSet.equal?(returned_devices, expected_devices)).to be_true()
      end
    end

    context "if passed query is :playback" do
      let :query, do: :playback

      it "should return all devices returned by the underlying enumerator for the same query regardless of its order" do
        # We are using MapSet to compare because order does not matter
        returned_devices = described_module().get_devices(server(), query(), timeout()) |> MapSet.new
        {:ok, expected_devices} = enumerator().list(query())
        expected_devices = expected_devices |> MapSet.new
        expect(MapSet.equal?(returned_devices, expected_devices)).to be_true()
      end
    end
  end
end
