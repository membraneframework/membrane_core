defmodule Membrane.Pipeline.CallbackContext do
  @moduledoc """
  Module describing context passed to the `Membrane.Pipeline` callbacks.
  """

  @typedoc """
  Type describing context passed to the `Membrane.Pipeline` callbacks.

  Field `:from` is present only in `c:Membrane.Pipeline.handle_call/3`.

  Field `:preceded_by_start_of_stream?` is present only in
  `c:Membrane.Pipeline.handle_element_end_of_stream/4`.

  Fields `:members` and `:crash_initiator` are present only in
  `c:Membrane.Pipeline.handle_crash_group_down/3`.
  """
  @type t :: %{
          :clock => Membrane.Clock.t(),
          :children => %{Membrane.Child.name() => Membrane.ChildEntry.t()},
          :playback => Membrane.Playback.t(),
          :resource_guard => Membrane.ResourceGuard.t(),
          :utility_supervisor => Membrane.UtilitySupervisor.t(),
          optional(:from) => [GenServer.from()],
          optional(:members) => [Membrane.Child.name()],
          optional(:crash_initiator) => Membrane.Child.name(),
          optional(:preceded_by_start_of_stream?) => boolean()
        }
end
