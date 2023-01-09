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
end
