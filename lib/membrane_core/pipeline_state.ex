defmodule Membrane.Pipeline.State do
  @moduledoc false
  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  use Membrane.Helper
  alias __MODULE__

  @type t :: %Membrane.Pipeline.State{
    internal_state: any,
    playback_state: Membrane.Mixins.Playback.state_t,
    module: module,
    children_to_pids: %{required([Membrane.Element.name_t]) => pid},
    pids_to_children: %{required(pid) => Membrane.Element.name_t},
  }

  defstruct \
    internal_state: nil,
    module: nil,
    children_to_pids: %{},
    pids_to_children: %{},
    playback_state: :stopped


    def get_child(%State{pids_to_children: pids_to_children}, child)
    when is_pid(child) do
      pids_to_children[child] |> Helper.wrap_nil({:unknown_child, child})
    end

    def get_child(%State{children_to_pids: children_to_pids}, child) do
      with {:ok, [pid|_]} <- children_to_pids[child] |> Helper.wrap_nil({:unknown_child, child}),
      do: {:ok, pid}
    end

    def pop_child(%State{children_to_pids: children_to_pids} = state, child) do
      with {:ok, pids} <- children_to_pids[child] |> Helper.wrap_nil({:unknown_child, child})
      do
        {pid, pids} = pids |> List.pop_at(-1)
        state = case pids do
            [] -> state |> Helper.Struct.remove_in([:children_to_pids, child])
            _ -> state |> Helper.Struct.put_in([:children_to_pids, child], pids)
          end
        state = state |> Helper.Struct.remove_in([:pids_to_children, pid])
        {{:ok, pid}, state}
      end
    end
end
