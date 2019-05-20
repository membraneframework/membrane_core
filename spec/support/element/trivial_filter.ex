defmodule Membrane.Support.Element.TrivialFilter do
  @moduledoc """
  This is the most basic filter. It does nothing, but is used in specs.
  """

  use Membrane.Element.Base.Filter

  def_output_pad :output, caps: :any

  def_input_pad :input, caps: :any, demand_unit: :buffers
end
