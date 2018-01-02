defmodule Membrane.Support.Element.TrivialSource do
  @moduledoc """
  This is minimal sample source element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """


  use Membrane.Element.Base.Source


  def_known_source_pads %{
    :source => {:always, :pull, :any}
  }


  def handle_init(_options) do
    {:ok, %{}}
  end
end
