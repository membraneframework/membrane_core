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
          | [
              group_name: Membrane.Child.group() | nil,
              crash_initiator: Membrane.Child.name() | nil,
              exit_reason: :normal | :shutdown | {:shutdown, term()} | term()
            ]

  @spec from_state(Membrane.Core.Pipeline.State.t(), optional_fields()) ::
          Membrane.Pipeline.CallbackContext.t()
  def from_state(state, optional_fields \\ []) do
    Map.new(optional_fields)
    |> Map.merge(%{
      clock: state.synchronization.clock_proxy,
      children: state.children,
      module: state.module,
      name: state.name,
      playback: state.playback,
      resource_guard: state.resource_guard,
      utility_supervisor: state.subprocess_supervisor
    })
  end
end
