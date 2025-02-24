defmodule Membrane.Core.Pipeline.CallbackContext do
  @moduledoc false

  @type optional_fields ::
          [from: GenServer.from()]
          | [
              members: [Membrane.Child.name()],
              crash_initiator: Membrane.Child.name(),
              crash_reason: :normal | :shutdown | {:shutdown, term()} | term()
            ]
          | [start_of_stream_received?: boolean()]

  @spec from_state(Membrane.Core.Pipeline.State.t(), optional_fields()) ::
          Membrane.Pipeline.CallbackContext.t()
  def from_state(state, optional_fields \\ []) do
    Map.new(optional_fields)
    |> Map.merge(%{
      clock: state.synchronization.clock_proxy,
      children: state.children,
      module: state.module,
      playback: state.playback,
      resource_guard: state.resource_guard,
      setup_incomplete_returned?: state.setup_incomplete_returned?,
      utility_supervisor: state.subprocess_supervisor
    })
  end
end
