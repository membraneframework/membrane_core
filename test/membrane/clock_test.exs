defmodule Membrane.ClockTest do
  @module Membrane.Clock

  use ExUnit.Case

  test "should send ratio once a new subscriber connects" do
    clock = @module.start_link!()
  end

  test "should calculate proper ratio and send it to all subscribers on each update" do
    clock = @module.start_link!()
  end
end
