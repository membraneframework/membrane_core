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

  Field `:crash_initiator` is only present in `c:Membrane.Bin.handle_child_terminated/3`
  and `c:Membrane.Bin.handle_crash_group_down/3`.

  Fields `:members` and `:crash_reason` are present only in
  `c:Membrane.Bin.handle_crash_group_down/3`.

  Fields `:exit_reason` and `:group_name` are present only in
  `c:Membrane.Bin.handle_child_terminated/3`.
  """
  @type t :: %{
          :children => %{Membrane.Child.name() => Membrane.ChildEntry.t()},
          :clock => Membrane.Clock.t(),
          :parent_clock => Membrane.Clock.t(),
          :module => module(),
          :name => Membrane.Bin.name(),
          :pads => %{Membrane.Pad.ref() => Membrane.Bin.PadData.t()},
          :playback => Membrane.Playback.t(),
          :resource_guard => Membrane.ResourceGuard.t(),
          :utility_supervisor => Membrane.UtilitySupervisor.t(),
          optional(:pad_options) => map(),
          optional(:members) => [Membrane.Child.name()],
          optional(:crash_initiator) => Membrane.Child.name() | nil,
          optional(:crash_reason) => :normal | :shutdown | {:shutdown, term()} | term(),
          optional(:start_of_stream_received?) => boolean(),
          optional(:exit_reason) => :normal | :shutdown | {:shutdown, term()} | term(),
          optional(:group_name) => Membrane.Child.group() | nil
        }
end
