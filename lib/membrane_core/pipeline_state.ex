defmodule Membrane.Pipeline.State do
  @moduledoc false
  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  @type t :: %Membrane.Pipeline.State{
    internal_state: any,
    module: module,
    children_to_pids: %{required(Membrane.Element.name_t) => pid},
    pids_to_children: %{required(pid) => Membrane.Element.name_t},
  }

  defstruct \
    internal_state: nil,
    module: nil,
    children_to_pids: %{},
    pids_to_children: %{}
end
