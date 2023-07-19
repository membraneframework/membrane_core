defmodule Membrane.Element.CallbackContext do
  @moduledoc """
  Describes context passed to the Membrane Element callbacks.
  """

  @typedoc """
  Type describing context passed to the Membrane Element callbacks.

  Field `:incoming_demand` is present only in
  `c:Membrane.Element.WithOutputPads.handle_demand/5`.

  Field `:pad_options` is present only in `c:Membrane.Element.Base.handle_pad_added/3`
  and `c:Membrane.Element.Base.handle_pad_removed/3`.

  Field `:start_of_stream_received?` is present only in
  `c:Membrane.Element.WithInputPads.handle_end_of_stream/3`.

  Field `:old_stream_format` is present only in
  `c:Membrane.Element.WithInputPads.handle_stream_format/4`.
  """
  @type t :: %{
          :pads => %{Membrane.Pad.ref() => Membrane.Element.PadData.t()},
          :clock => Membrane.Clock.t() | nil,
          :parent_clock => Membrane.Clock.t() | nil,
          :name => Membrane.Element.name(),
          :playback => Membrane.Playback.t(),
          :resource_guard => Membrane.ResourceGuard.t(),
          :utility_supervisor => Membrane.UtilitySupervisor.t(),
          optional(:incoming_demand) => non_neg_integer(),
          optional(:pad_options) => map(),
          optional(:old_stream_format) => Membrane.StreamFormat.t(),
          optional(:start_of_stream_received?) => boolean()
        }
end
