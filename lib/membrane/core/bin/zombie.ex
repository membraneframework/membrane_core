defmodule Membrane.Core.Bin.Zombie do
  @moduledoc false
  # When a bin returns Membrane.Bin.Action.terminate_t() and becomes a zombie
  # this module is used to replace the user implementation of the bin
  use Membrane.Bin
end
