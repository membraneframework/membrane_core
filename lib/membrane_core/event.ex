defmodule Membrane.Event do
  @moduledoc """
  Structure representing a single event that flows between elements.

  Each buffer:

  - must contain type,
  - may contain payload,
  """

  @type t :: %Membrane.Event{
    type: atom,
    payload: map
  }

  defstruct \
    type: nil,
    payload: nil


  @doc """
  Shorthand for creating a generic End of Stream downstream event.
  """
  @spec eos() :: t
  def eos() do
    %Membrane.Event{type: :eos}
  end


  @doc """
  Shorthand for creating a generic Discontinuity downstream event.
  """
  @spec discontinuity() :: t
  def discontinuity() do
    %Membrane.Event{type: :discontinuity}
  end
end
