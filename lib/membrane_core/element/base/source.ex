defmodule Membrane.Element.Base.Source do
  @moduledoc """
  This module should be used by all elements that are sources.
  """


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.Process
      use Membrane.Element.Base.Mixin.Source
    end
  end
end
