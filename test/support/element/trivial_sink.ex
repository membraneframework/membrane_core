defmodule Membrane.Support.Element.TrivialSink do
  @moduledoc """
  This is the most basic sink. It does nothing, but is used in tests.
  """

  use Membrane.Sink

  def_input_pad :input, caps: _any, demand_unit: :buffers
end
