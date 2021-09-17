defmodule Membrane.Pipeline.CallbackContext.CrashGroupDown do
  @moduledoc """
  Structure representing a context that is passed to the bin
  when a crash group is down.
  """
  use Membrane.Core.Pipeline.CallbackContext,
    members: [Membrane.Child.name_t()],
    first_crashed_child: Membrane.Child.name_t()
end
