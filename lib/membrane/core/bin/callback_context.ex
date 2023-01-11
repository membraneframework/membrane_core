defmodule Membrane.Core.Bin.CallbackContext do
  @moduledoc false

  @type optional_fields_t :: [pad_options: map()]

  @spec from_state(Membrane.Core.Bin.State.t(), optional_fields_t()) ::
          Membrane.Bin.CallbackContext.t()
  def from_state(state, optional_fields \\ []) do
    Map.new(optional_fields)
    |> Map.merge(%{
      clock: state.synchronization.clock,
      parent_clock: state.synchronization.parent_clock,
      pads: state.pads_data,
      name: state.name,
      children: state.children,
      playback: state.playback,
      resource_guard: state.resource_guard,
      utility_supervisor: state.subprocess_supervisor
    })
  end
end
