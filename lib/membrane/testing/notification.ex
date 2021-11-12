defmodule Membrane.Testing.Notification do
  @moduledoc false

  # Notification sent internally by `Membrane.Testing.Pipeline`
  @enforce_keys [:payload]
  defstruct @enforce_keys
end
