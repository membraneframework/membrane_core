defmodule Membrane.Core.Pipeline.CallbackContext do
  @moduledoc false

  @type option_t ::
          {:from, [GenServer.from()]}
          | {:members, [Membrane.Child.name_t()]}
          | {:crash_initiator, Membrane.Child.name_t()}

  @type options_t :: [option_t()]

  @spec from_state(Membrane.Core.Pipeline.State.t(), options_t()) ::
          Membrane.Pipeline.CallbackContext.t()
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
