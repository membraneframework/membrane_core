defmodule Membrane.Support.Element.TrivialFilter do
  @moduledoc """
  This is minimal sample filter element for use in specs.

  Modify with caution as many specs may depend on its shape.
  """


  use Membrane.Element.Base.Filter


  def known_source_pads(), do: %{
    :source => {:always, :any}
  }


  def known_sink_pads(), do: %{
    :sink => {:always, :any}
  }


  def handle_init(_options) do
    {:ok, %{}}
  end


  def handle_buffer(_buffer, state) do
    {:ok, state}
  end
end
