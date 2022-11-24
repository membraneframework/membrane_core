defmodule Membrane.Core.Pipeline.CallbackContext do
  @moduledoc false

  use Membrane.Core.CallbackContext,
    clock: Membrane.Clock.t(),
    children: %{Membrane.Child.name_t() => Membrane.ChildEntry.t()},
    playback: Membrane.Playback.t(),
    resource_guard: Membrane.ResourceGuard.t(),
    utility_supervisor: Membrane.UtilitySupervisor.t()

  @impl true
  def extract_default_fields(state, args) do
    quote do
      [
        clock: unquote(state).synchronization.clock_proxy,
        children: unquote(state).children,
        playback: unquote(state).playback,
        resource_guard: unquote(state).resource_guard,
        utility_supervisor: unquote(state).subprocess_supervisor
      ]
    end ++ args
  end
end
