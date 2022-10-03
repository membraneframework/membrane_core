defmodule Membrane.Support.Elements.TrivialFilter do
  @moduledoc """
  This is the most basic filter. It does nothing, but is used in tests.
  """

  use Membrane.Filter

  def_output_pad :output, caps: :any

  def_input_pad :input, caps: :any, demand_unit: :buffers
end
