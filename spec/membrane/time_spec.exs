defmodule Membrane.TimeSpec do
  use ESpec, async: true

  describe ".nanoseconds/1" do
    let :value, do: 123

    it "should return given value" do
      expect(described_module().nanoseconds(value())) |> to(eq value())
    end
  end

  describe ".microseconds/1" do
    let :value, do: 123

    it "should return given value multiplied by 1000" do
      expect(described_module().microseconds(value())) |> to(eq value() * 1_000)
    end
  end

  describe ".milliseconds/1" do
    let :value, do: 123

    it "should return given value multiplied by 1000000" do
      expect(described_module().milliseconds(value())) |> to(eq value() * 1_000_000)
    end
  end

  describe ".seconds/1" do
    let :value, do: 123

    it "should return given value multiplied by 1000000000" do
      expect(described_module().seconds(value())) |> to(eq value() * 1_000_000_000)
    end
  end

  describe ".minutes/1" do
    let :value, do: 123

    it "should return given value multiplied by 60000000000" do
      expect(described_module().minutes(value())) |> to(eq value() * 60_000_000_000)
    end
  end

  describe ".hours/1" do
    let :value, do: 123

    it "should return given value multiplied by 3600000000000" do
      expect(described_module().hours(value())) |> to(eq value() * 3_600_000_000_000)
    end
  end

  describe ".days/1" do
    let :value, do: 123

    it "should return given value multiplied by 86400000000000" do
      expect(described_module().days(value())) |> to(eq value() * 86_400_000_000_000)
    end
  end

  describe ".native_units/1" do
    it "should return time converted into erlang native units" do
      expect(1 |> described_module().seconds |> described_module().native_units)
      |> to(eq :erlang.convert_time_unit(1, :seconds, :native))
    end
  end

  describe "monotonic_time/0" do
    it "should return integer" do
      expect(described_module().monotonic_time) |> to(be_integer())
    end
  end
end
