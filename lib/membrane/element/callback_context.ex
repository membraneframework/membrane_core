defmodule Membrane.Element.CallbackContext do
  @moduledoc false

  @type t :: %{
          :pads => %{Membrane.Pad.ref_t() => Membrane.Element.PadData.t()},
          :clock => Membrane.Clock.t() | nil,
          :parent_clock => Membrane.Clock.t() | nil,
          :name => Membrane.Element.name_t(),
          :playback => Membrane.Playback.t(),
          :resource_guard => Membrane.ResourceGuard.t(),
          :utility_supervisor => Membrane.UtilitySupervisor.t(),
          optional(:incoming_demand) => non_neg_integer(),
          optional(:pad_options) => map(),
          optional(:old_stream_format) => Membrane.StreamFormat.t()
        }

  @type option_t ::
          {:incoming_demand, non_neg_integer()}
          | {:pad_options, map()}
          | {:old_stream_format, Membrane.StreamFormat.t()}

  @type options_t :: [option_t()]

  @spec from_state(Membrane.Core.Element.State.t(), options_t()) :: t()
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
