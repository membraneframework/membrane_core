defmodule Membrane.Core.Pipeline.CallbackContext do
  @moduledoc false

  @type optional_fields_t ::
          [from: GenServer.from()]
          | [members: [Membrane.Child.name_t()], crash_initiator: Membrane.Child.name_t()]

  @spec from_state(Membrane.Core.Pipeline.State.t(), optional_fields_t()) ::
          Membrane.Pipeline.CallbackContext.t()
  def from_state(state, optional_fields \\ []) do
    Map.new(optional_fields)
    |> Map.merge(%{
      clock: state.synchronization.clock_proxy,
      children: state.children,
      playback: state.playback,
      resource_guard: state.resource_guard,
      utility_supervisor: state.subprocess_supervisor
    })
  end
end
