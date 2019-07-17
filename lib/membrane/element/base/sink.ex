defmodule Membrane.Element.Base.Sink do
  @deprecated "Use `Membrane.Sink` instead"

  defmacro __using__(_opts) do
    quote do
      use Membrane.Sink
    end
  end
end
