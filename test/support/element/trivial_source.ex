defmodule Membrane.Support.Element.TrivialSource do
  @moduledoc """
  This is the most basic source. It does nothing, but is used in specs.
  """

  use Bunch
  use Membrane.Source

  def_output_pad :output, caps: :any
end
