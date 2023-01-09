defmodule Membrane.Bin.CallbackContext do
  @moduledoc """
  Module describiing context passed to the `Membrane.Bin` callbacks.
  """

  @type t :: %{
          :clock => Membrane.Clock.t(),
          :parent_clock => Membrane.Clock.t(),
          :pads => %{Membrane.Pad.ref_t() => Membrane.Bin.PadData.t()},
          :name => Membrane.Bin.name_t(),
          :children => %{Membrane.Child.name_t() => Membrane.ChildEntry.t()},
          :playback => Membrane.Playback.t(),
          :resource_guard => Membrane.ResourceGuard.t(),
          :utility_supervisor => Membrane.UtilitySupervisor.t(),
          optional(:pad_options) => map()
        }

  @type option_t() :: {:pad_options, map()}

  @type options_t :: [option_t()]

  @spec from_state(Membrane.Core.Bin.State.t(), options_t()) :: t()
  def from_state(state, additional_fields \\ []) do
    Map.new(additional_fields)
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
