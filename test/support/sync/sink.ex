defmodule Membrane.Support.Sync.Sink do
  @moduledoc false
  use Membrane.Sink

  def_input_pad :input, flow_control: :manual, accepted_format: _any, demand_unit: :buffers

  def_clock()
end
