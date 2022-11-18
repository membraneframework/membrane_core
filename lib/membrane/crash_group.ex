defmodule Membrane.CrashGroup do
  @moduledoc """
  Module containing types and functions for operating on crash groups.
  Crash groups can be used through `Membrane.ChildrenSpec`.
  """
  @type mode_t() :: :temporary | nil
  @type name_t() :: any()
  @type t :: {name_t, mode_t}
end
