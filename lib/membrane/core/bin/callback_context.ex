defmodule Membrane.Core.Bin.CallbackContext do
  @moduledoc false

  @type optional_fields ::
          [pad_options: map()]
          | [
              members: [Membrane.Child.name()],
              crash_initiator: Membrane.Child.name(),
              crash_reason: :normal | :shutdown | {:shutdown, term()} | term()
            ]
          | [start_of_stream_received?: boolean()]

  @spec from_state(Membrane.Core.Bin.State.t(), optional_fields()) ::
          Membrane.Bin.CallbackContext.t()
  def from_state(state, optional_fields \\ []) do
    Map.new(optional_fields)
    |> Map.merge(%{
      children: state.children,
      clock: state.synchronization.clock,
      parent_clock: state.synchronization.parent_clock,
      pads: state.pads_data,
      module: state.module,
      name: state.name,
      playback: state.playback,
      resource_guard: state.resource_guard,
      setup_incomplete_returned?: state.setup_incomplete_returned?,
      utility_supervisor: state.subprocess_supervisor
    })
  end
end
