defmodule Membrane.EventSpec do
  use ESpec, async: true

  describe "when creating new struct" do
    it "should have type field set to nil" do
      %Membrane.Event{type: type} = struct(described_module())
      expect(type).to be_nil()
    end

    it "should have payload field set to nil" do
      %Membrane.Event{payload: payload} = struct(described_module())
      expect(payload).to be_nil()
    end
  end


  describe ".eos/0" do
    it "should return a Membrane.Event with type set to :eos" do
      %Membrane.Event{type: type} = described_module().eos
      expect(type).to be :eos
    end

    it "should return a Membrane.Event with payload set to nil" do
      %Membrane.Event{payload: payload} = described_module().eos
      expect(payload).to be_nil()
    end
  end


  describe ".discontinuity/1" do
    let :duration, do: 1234

    it "should return a Membrane.Event with type set to :discontinuity" do
      %Membrane.Event{type: type} = described_module().discontinuity(duration())
      expect(type).to be :discontinuity
    end

    it "should return a Membrane.Event with payload set to Membrane.Event.Discontinuity.Payload with duration equal to given duration" do
      %Membrane.Event{payload: payload} = described_module().discontinuity(duration())
      expect(payload).to eq %Membrane.Event.Discontinuity.Payload{duration: duration()}
    end
  end
end
