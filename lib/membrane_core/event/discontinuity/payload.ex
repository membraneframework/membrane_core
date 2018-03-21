defmodule Membrane.Event.Discontinuity.Payload do
  @moduledoc """
  Structure representing a payload for the Discontinuity event.
  """

  # Discontinuity duration in nanoseconds or nil if it is unknown.
  @type duration_t :: pos_integer | nil

  @type t :: %Membrane.Event.Discontinuity.Payload{
          duration: duration_t
        }

  defstruct duration: nil
end
