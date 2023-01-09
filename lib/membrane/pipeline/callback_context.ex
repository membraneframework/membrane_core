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

  @type option_t ::
          {:from, [GenServer.from()]}
          | {:members, [Membrane.Child.name_t()]}
          | {:crash_initiator, Membrane.Child.name_t()}

  @type options_t :: [option_t()]

  @spec from_state(Membrane.Core.Bin.State.t(), options_t()) :: t()
  def from_state(state, additional_fields \\ []) do
    Map.new(additional_fields)
    |> Map.merge(%{
      clock: state.synchronization.clock_proxy,
      children: state.children,
      playback: state.playback,
      resource_guard: state.resource_guard,
      utility_supervisor: state.subprocess_supervisor
    })
  end
end
