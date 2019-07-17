defmodule Membrane.Element.Base.Filter do
  @deprecated "Use `Membrane.Filter` instead"

  defmacro __using__(_opts) do
    quote do
      use Membrane.Filter
    end
  end
end
