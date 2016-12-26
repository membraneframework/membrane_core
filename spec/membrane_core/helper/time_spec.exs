defmodule Membrane.Helper.TimeSpec do
  use ESpec, async: false


  describe ".resolution/0" do
    it "should return 1 second converted into erlang native units" do
      expect(described_module.resolution).to eq :erlang.convert_time_unit(1, :seconds, :native)
    end
  end


  describe ".monotonic_time/0" do
    it "should return integer" do
      expect(described_module.monotonic_time).to be_integer
    end
  end
end
