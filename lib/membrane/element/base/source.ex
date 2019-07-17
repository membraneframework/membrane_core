defmodule Membrane.Element.Base.Source do
  @deprecated "Use Membrane.Source instead"

  defmacro __using__(_opts) do
    quote do
      use Membrane.Source
    end
  end
end
