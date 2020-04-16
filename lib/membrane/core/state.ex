defmodule Membrane.Core.State do
  alias Membrane.Core

  @type t :: Core.Parent.State.t() | Core.Child.State.t() | Core.Element.State.t()
end
