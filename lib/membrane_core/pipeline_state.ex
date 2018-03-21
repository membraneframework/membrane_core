defmodule Membrane.Pipeline.State do
  @moduledoc false
  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  use Membrane.Helper
  alias __MODULE__
  alias Membrane.Mixins.{Playback, Playbackable}

  @derive Playbackable

  @type t :: %Membrane.Pipeline.State{
          internal_state: any,
          playback: Playback.t(),
          module: module,
          children_to_pids: %{required([Membrane.Element.name_t()]) => pid},
          pids_to_children: %{required(pid) => Membrane.Element.name_t()},
          children_ids: %{atom => integer},
          pending_pids: list(pid),
          terminating?: boolean
        }

  @type internal_state_t :: any

  defstruct internal_state: nil,
            module: nil,
            children_to_pids: %{},
            pids_to_children: %{},
            playback: %Playback{},
            pending_pids: nil,
            children_ids: %{},
            terminating?: false

  # FIXME: rename to get_child_name_by_pid
  def get_child(%State{pids_to_children: pids_to_children}, child)
      when is_pid(child) do
    pids_to_children[child] |> Helper.wrap_nil({:unknown_child, child})
  end

  def get_child(%State{children_to_pids: children_to_pids}, child) do
    with {:ok, pid} <- children_to_pids[child] |> Helper.wrap_nil({:unknown_child, child}),
         do: {:ok, pid}
  end

  def pop_child(state, child) do
    {pid, children_to_pids} = state.children_to_pids |> Map.pop(child)

    with {:ok, pid} <- pid |> Helper.wrap_nil({:unknown_child, child}) do
      state = %State{
        state
        | children_to_pids: children_to_pids,
          pids_to_children: state.pids_to_children |> Map.delete(pid)
      }

      {{:ok, pid}, state}
    end
  end

  def get_increase_child_id(state, child) do
    state
    |> Helper.Struct.get_and_update_in(
      [:children_ids, child],
      &((&1 || 0) ~> (id -> {id, id + 1}))
    )
  end

  def is_dynamic?(state, child) do
    state.children_ids[child] != nil
  end

  def get_last_child_id(state, child) do
    with {:ok, id} <- state.children_ids[child] |> Helper.wrap_nil(:not_dynamic) do
      {:ok, id - 1}
    end
  end
end
