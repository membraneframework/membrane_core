defmodule Membrane.CrashGroup do
  @moduledoc """
  Module containing types and functions for operating on crash groups.
  Crash groups can be used through `Membrane.ParentSpec`.
  """
  @type mode_t() :: :temporary | nil
  @type name_t() :: any()
end
