defmodule Membrane.Element.Base.Filter do
  @moduledoc """
  This module should be used by all elements that are both sources and sinks.
  """


  defmacro __using__(_) do
    quote do
      use Membrane.Element.Base.Source
      use Membrane.Element.Base.Sink
    end
  end
end
