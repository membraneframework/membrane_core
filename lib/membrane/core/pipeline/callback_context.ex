defmodule Membrane.Core.Pipeline.CallbackContext do
  @moduledoc false

  use Membrane.Core.CallbackContext,
    clock: Membrane.Clock.t(),
    children: %{Membrane.Child.name_t() => Membrane.ChildEntry.t()}

  @impl true
  def extract_default_fields(state, args) do
    quote do
      [
        clock: unquote(state).synchronization.clock_proxy,
        children: unquote(state).children
      ]
    end ++ args
  end
end
