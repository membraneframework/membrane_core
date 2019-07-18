defmodule Membrane.Element.Base.Source do
  @moduledoc """
  This module has been deprecated in favour of `Membrane.Source`.
  """

  @deprecated "Use `Membrane.Source` instead"
  defmacro __using__(_opts) do
    quote do
      use Membrane.Source
    end
  end
end
