defmodule Membrane.Element.CallbackContext do
  @moduledoc """
  Describes context passed to Membrane Elements callbacks.
  """

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
end
