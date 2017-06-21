defmodule Membrane.Pad.State do
  @moduledoc false
  # Structure representing state of a pad. It is a part of the private API.

  @type t :: %Membrane.Pad.State{
    internal_state: any,
    direction: Membrane.Pad.direction_t,
    module: module,
    parent: pid,
    peer: pid,
    active: boolean,
  }

  defstruct \
    internal_state: nil,
    direction: nil,
    module: nil,
    parent: nil,
    peer: nil,
    active: false,
    name: nil


  @spec new(pid, Pad.name_t, Membrane.Pad.direction_t, module, any) :: t
  def new(parent, name, direction, module, internal_state) do
    %Membrane.Pad.State{
      parent: parent,
      direction: direction,
      module: module,
      internal_state: internal_state,
      name: name
    }
  end
end
