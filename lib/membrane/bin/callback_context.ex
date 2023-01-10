defmodule Membrane.Bin.CallbackContext do
  @moduledoc """
  Module describing context passed to the `Membrane.Bin` callbacks.
  """

  @typedoc """
  Type describing context passed to the `Membrane.Bin` callbacks.

  Field `:pad_options` is present only in `c:Membrane.Bin.handle_pad_added/3`
  and `c:Membrane.Bin.handle_pad_removed/3`.
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
