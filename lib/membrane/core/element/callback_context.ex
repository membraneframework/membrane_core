defmodule Membrane.Core.Element.CallbackContext do
  @moduledoc false

  @type option_t ::
          {:incoming_demand, non_neg_integer()}
          | {:pad_options, map()}
          | {:old_stream_format, Membrane.StreamFormat.t()}

  @type options_t :: [option_t()]

  @spec from_state(Membrane.Core.Element.State.t(), options_t()) ::
          Membrane.Element.CallbackContext.t()
  def from_state(state, additional_fields \\ []) do
    Map.new(additional_fields)
    |> Map.merge(%{
      pads: state.pads_data,
      clock: state.synchronization.clock,
      parent_clock: state.synchronization.parent_clock,
      name: state.name,
      playback: state.playback,
      resource_guard: state.resource_guard,
      utility_supervisor: state.subprocess_supervisor
    })
  end
end
