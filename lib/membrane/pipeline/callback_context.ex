defmodule Membrane.Pipeline.CallbackContext do
  @moduledoc """
  Module describing context passed to the `Membrane.Pipeline` callbacks.
  """

  @type t :: %{
          :clock => Membrane.Clock.t(),
          :children => %{Membrane.Child.name_t() => Membrane.ChildEntry.t()},
          :playback => Membrane.Playback.t(),
          :resource_guard => Membrane.ResourceGuard.t(),
          :utility_supervisor => Membrane.UtilitySupervisor.t(),
          optional(:from) => [GenServer.from()],
          optional(:members) => [Membrane.Child.name_t()],
          optional(:crash_initiator) => Membrane.Child.name_t()
        }
end
