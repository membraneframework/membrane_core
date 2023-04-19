defmodule Membrane.Core.Element.CallbackContext do
  @moduledoc false

  alias Membrane.Child

  @type optional_fields ::
          [incoming_demand: non_neg_integer()]
          | [options: map()]
          | [old_stream_format: Membrane.StreamFormat.t()]

  @spec from_state(Membrane.Core.Element.State.t(), optional_fields()) ::
          Membrane.Element.CallbackContext.t()
  def from_state(state, optional_fields \\ []) do
    Map.new(optional_fields)
    |> Map.merge(%{
      pads: state.pads_data,
      clock: state.synchronization.clock,
      parent_clock: state.synchronization.parent_clock,
      name: Child.name_by_ref(state.name),
      ref: state.name,
      playback: state.playback,
      resource_guard: state.resource_guard,
      utility_supervisor: state.subprocess_supervisor
    })
  end
end
