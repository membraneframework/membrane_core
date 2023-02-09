defmodule Membrane.CrashGroup do
  @moduledoc """
  Module containing types and functions for operating on crash groups.
  Crash groups can be used through `Membrane.ChildrenSpec`.
  """
  @type mode() :: :temporary | nil
  @type name() :: any()
  @type t :: {name, mode}
end
