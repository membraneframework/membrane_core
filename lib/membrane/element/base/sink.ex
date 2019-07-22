defmodule Membrane.Element.Base.Sink do
  @moduledoc """
  This module has been deprecated in favour of `Membrane.Sink`.
  """

  @deprecated "Use `Membrane.Sink` instead"
  defmacro __using__(_opts) do
    quote do
      use Membrane.Sink
    end
  end
end
