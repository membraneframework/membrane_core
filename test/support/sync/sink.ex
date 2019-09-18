defmodule Membrane.Support.Sync.Sink do
  use Membrane.Sink

  def_input_pad :input, caps: :any, demand_unit: :buffers

  def_clock()
end
