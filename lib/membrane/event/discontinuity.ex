defmodule Membrane.Event.Discontinuity do
  @moduledoc """
  Generic discontinuity event.

  This event means that flow of buffers in the stream was interrupted, but stream
  itself is not done.

  Frequent reasons for this are soundcards drops while capturing sound, network
  data loss etc.

  If duration of the discontinuity is known, it can be passed as an argument.
  """

  use Membrane.Event, async?: fn _ -> true end, sticky?: fn _ -> true end

  @type duration_t :: Membrane.Time.t() | nil

  def_event_struct duration: [default: nil, type: duration_t], metadata: [default: "jeheheeh"]
end
