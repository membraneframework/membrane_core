defmodule Membrane.Support.Element.TrivialSink do
  @moduledoc """
  This is the most basic sink. It does nothing, but is used in tests.
  """

  use Membrane.Sink

  def_input_pad :input, accepted_format: _any, demand_unit: :buffers
end
