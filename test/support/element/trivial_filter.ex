defmodule Membrane.Support.Element.TrivialFilter do
  @moduledoc """
  This is the most basic filter. It does nothing, but is used in tests.
  """

  use Membrane.Filter

  def_output_pad :output, accepted_format: _any

  def_input_pad :input, accepted_format: _any, demand_unit: :buffers
end
