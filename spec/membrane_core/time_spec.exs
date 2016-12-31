defmodule Membrane.TimeSpec do
  use ESpec, async: true

  describe ".nanosecond/1" do
    let :value, do: 123

    it "should return given value" do
      expect(described_module.nanosecond(value)).to eq value
    end
  end

  describe ".nanoseconds/1" do
    let :value, do: 123

    it "should return given value" do
      expect(described_module.nanoseconds(value)).to eq value
    end
  end

  describe ".microsecond/1" do
    let :value, do: 123

    it "should return given value multiplied by 1000" do
      expect(described_module.microsecond(value)).to eq value * 1_000
    end
  end

  describe ".microseconds/1" do
    let :value, do: 123

    it "should return given value multiplied by 1000" do
      expect(described_module.microseconds(value)).to eq value * 1_000
    end
  end

  describe ".millisecond/1" do
    let :value, do: 123

    it "should return given value multiplied by 1000000" do
      expect(described_module.millisecond(value)).to eq value * 1_000_000
    end
  end

  describe ".milliseconds/1" do
    let :value, do: 123

    it "should return given value multiplied by 1000000" do
      expect(described_module.milliseconds(value)).to eq value * 1_000_000
    end
  end

  describe ".second/1" do
    let :value, do: 123

    it "should return given value multiplied by 1000000000" do
      expect(described_module.second(value)).to eq value * 1_000_000_000
    end
  end

  describe ".seconds/1" do
    let :value, do: 123

    it "should return given value multiplied by 1000000000" do
      expect(described_module.seconds(value)).to eq value * 1_000_000_000
    end
  end

  describe ".minute/1" do
    let :value, do: 123

    it "should return given value multiplied by 60000000000" do
      expect(described_module.minute(value)).to eq value * 60_000_000_000
    end
  end

  describe ".minutes/1" do
    let :value, do: 123

    it "should return given value multiplied by 60000000000" do
      expect(described_module.minutes(value)).to eq value * 60_000_000_000
    end
  end

  describe ".hour/1" do
    let :value, do: 123

    it "should return given value multiplied by 3600000000000" do
      expect(described_module.hour(value)).to eq value * 3_600_000_000_000
    end
  end

  describe ".hours/1" do
    let :value, do: 123

    it "should return given value multiplied by 3600000000000" do
      expect(described_module.hours(value)).to eq value * 3_600_000_000_000
    end
  end

  describe ".day/1" do
    let :value, do: 123

    it "should return given value multiplied by 86400000000000" do
      expect(described_module.day(value)).to eq value * 86_400_000_000_000
    end
  end

  describe ".days/1" do
    let :value, do: 123

    it "should return given value multiplied by 86400000000000" do
      expect(described_module.days(value)).to eq value * 86_400_000_000_000
    end
  end


  describe ".native_resolution/0" do
    it "should return 1 second converted into erlang native units" do
      expect(described_module.native_resolution).to eq :erlang.convert_time_unit(1, :seconds, :native)
    end
  end


  describe ".native_monotonic_time/0" do
    it "should return integer" do
      expect(described_module.native_monotonic_time).to be_integer
    end
  end
end
