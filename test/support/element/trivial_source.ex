defmodule Membrane.Support.Element.TrivialSource do
  @moduledoc """
  This is the most basic source. It does nothing, but is used in tests.
  """

  use Bunch
  use Membrane.Source

  def_output_pad :output, flow_control: :manual, accepted_format: _any
end
