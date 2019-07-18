defmodule Membrane.Element.Base.Filter do
  @moduledoc """
  This module has been deprecated in favour of `Membrane.Filter`.
  """

  @deprecated "Use `Membrane.Filter` instead"
  defmacro __using__(_opts) do
    quote do
      use Membrane.Filter
    end
  end
end
