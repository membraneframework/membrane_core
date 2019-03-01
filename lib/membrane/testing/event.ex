defmodule Membrane.Testing.Event do
  @moduledoc """
  Empty event that can be used in tests
  """

  @derive Membrane.EventProtocol
  defstruct []
end
