defmodule Membrane.Bin.CallbackContext do
  @moduledoc """
  Module describing context passed to the `Membrane.Bin` callbacks.
  """

  @typedoc """
  Type describing context passed to the `Membrane.Bin` callbacks.

  Field `:pad_options` is present only in `c:Membrane.Bin.handle_pad_added/3`
  and `c:Membrane.Bin.handle_pad_removed/3`.

  Field `:start_of_stream_received?` is present only in
  `c:Membrane.Bin.handle_element_end_of_stream/4`.

  Fields `:members` and `:crash_initiator` are present only in
  `c:Membrane.Pipeline.handle_crash_group_down/3`.
  """
  @type t :: %{
          :clock => Membrane.Clock.t(),
          :parent_clock => Membrane.Clock.t(),
          :pads => %{Membrane.Pad.ref() => Membrane.Bin.PadData.t()},
          :name => Membrane.Bin.name(),
          :children => %{Membrane.Child.name() => Membrane.ChildEntry.t()},
          :playback => Membrane.Playback.t(),
          :resource_guard => Membrane.ResourceGuard.t(),
          :utility_supervisor => Membrane.UtilitySupervisor.t(),
          optional(:pad_options) => map(),
          optional(:members) => [Membrane.Child.name()],
          optional(:crash_initiator) => Membrane.Child.name(),
          optional(:start_of_stream_received?) => boolean()
        }
end
