defmodule Membrane.Core.Element.CallbackContext do
  @moduledoc false

  @type optional_fields ::
          [incoming_demand: non_neg_integer()]
          | [pad_options: map()]
          | [old_stream_format: Membrane.StreamFormat.t()]
          | [start_of_stream_received?: boolean()]

  @spec from_state(Membrane.Core.Element.State.t(), optional_fields()) ::
          Membrane.Element.CallbackContext.t()
  def from_state(state, optional_fields \\ []) do
    Map.new(optional_fields)
    |> Map.merge(%{
      pads: state.pads_data,
      clock: state.synchronization.clock,
      parent_clock: state.synchronization.parent_clock,
      name: state.name,
      playback: state.playback,
      resource_guard: state.resource_guard,
      utility_supervisor: state.subprocess_supervisor,
      big_state: state
    })
  end
end
