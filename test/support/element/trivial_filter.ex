defmodule Membrane.Support.Element.TrivialFilter do
  @moduledoc """
  This is the most basic filter. It does nothing, but is used in tests.
  """

  use Membrane.Filter

  def_output_pad :output, caps: _any

  def_input_pad :input, caps: _any, demand_unit: :buffers
end
