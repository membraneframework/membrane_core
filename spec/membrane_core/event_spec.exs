defmodule Membrane.EventSpec do
  use ESpec, async: true

  def should_have_type(event, target_type) do
    %Membrane.Event{type: type} = struct(event)
    expect(type) |> to(eq target_type)
  end

  def should_have_payload(event, target_payload) do
    %Membrane.Event{payload: payload} = struct(event)
    expect(payload) |> to(eq target_payload)
  end

  describe "when creating new struct" do
    it "should have type field set to nil" do
      should_have_type(described_module(), nil)
    end

    it "should have payload field set to nil" do
      should_have_payload(described_module(), nil)
    end
  end

  describe ".eos/0" do
    it "should return a Membrane.Event with type set to :eos" do
      should_have_type(described_module().eos, :eos)
    end

    it "should return a Membrane.Event with payload set to nil" do
      should_have_payload(described_module().eos, nil)
    end
  end

  describe ".underrun/0" do
    it "should return a Membrane.Event with type set to :underrun" do
      should_have_type(described_module().underrun, :underrun)
    end

    it "should return a Membrane.Event with payload set to nil" do
      should_have_payload(described_module().underrun, nil)
    end
  end

  describe ".discontinuity/1" do
    let :duration, do: 1234

    it "should return a Membrane.Event with type set to :discontinuity" do
      should_have_type(described_module().discontinuity(duration()), :discontinuity)
    end

    it "should return a Membrane.Event with payload set to Membrane.Event.Discontinuity.Payload with duration equal to given duration" do
      should_have_payload(
        described_module().discontinuity(duration()),
        %Membrane.Event.Discontinuity.Payload{duration: duration()}
      )
    end
  end
end
