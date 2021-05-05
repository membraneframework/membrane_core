defmodule Membrane.KeyframeRequestEvent do
  @moduledoc """
  Generic event for requesting a key frame.

  The key frame is meant as a part of stream such that
  the stream can be decoded from the beginning of each key
  frame without knowledge of the stream content before that
  point.
  """
  @derive Membrane.EventProtocol

  defstruct []

  @type t :: %__MODULE__{}
end
