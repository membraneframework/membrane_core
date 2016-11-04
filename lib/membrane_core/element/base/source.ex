defmodule Membrane.Element.Base.Source do
  @moduledoc """
  This module should be used by all elements that are sources.
  """


  defmacro __using__(_) do
    quote do
      use Membrane.Element.Base.Mixin.Process

    end
  end
end
