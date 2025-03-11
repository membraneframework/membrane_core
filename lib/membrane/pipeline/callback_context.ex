defmodule Membrane.Pipeline.CallbackContext do
  @moduledoc """
  Module describing context passed to the `Membrane.Pipeline` callbacks.
  """

  @typedoc """
  Type describing context passed to the `Membrane.Pipeline` callbacks.

  Field `:from` is present only in `c:Membrane.Pipeline.handle_call/3`.

  Field `:start_of_stream_received?` is present only in
  `c:Membrane.Pipeline.handle_element_end_of_stream/4`.

  Fields `:members`, `:crash_initiator` and `:crash_reason` are present only in
  `c:Membrane.Pipeline.handle_crash_group_down/3`.
  """
  @type t :: %{
          :children => %{Membrane.Child.name() => Membrane.ChildEntry.t()},
          :clock => Membrane.Clock.t(),
          :module => module(),
          :name => term(),
          :playback => Membrane.Playback.t(),
          :resource_guard => Membrane.ResourceGuard.t(),
          :utility_supervisor => Membrane.UtilitySupervisor.t(),
          optional(:from) => [GenServer.from()],
          optional(:members) => [Membrane.Child.name()],
          optional(:crash_initiator) => Membrane.Child.name(),
          optional(:crash_reason) => :normal | :shutdown | {:shutdown, term()} | term(),
          optional(:start_of_stream_received?) => boolean()
        }
end
