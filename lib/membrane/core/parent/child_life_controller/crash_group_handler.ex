defmodule Membrane.Core.Parent.ChildLifeController.CrashGroupHandler do
  @moduledoc """
  A module responsible for managing crash groups inside the state of pipeline.
  """

  alias Membrane.ParentSpec
  alias Membrane.Core.Pipeline
  alias Membrane.Core.Parent.CrashGroup

  @spec add_crash_group(
          ParentSpec.crash_group_spec_t(),
          [Membrane.Child.name_t()],
          [pid()],
          Pipeline.State.t()
        ) ::
          {:ok, Pipeline.State.t()}
  def add_crash_group(group_spec, children_names, children_pids, state) do
    {group_name, mode} = group_spec

    crash_group = %CrashGroup{
      name: group_name,
      mode: mode,
      members: children_names,
      alive_members: children_pids
    }

    state = %{
      state
      | crash_groups:
          Map.update(
            state.crash_groups,
            group_name,
            crash_group,
            fn %CrashGroup{members: current_children_names, alive_members: current_alive_members} = existing_group ->
              %{existing_group | members: current_children_names ++ children_names, alive_members: current_alive_members ++ children_pids}
            end
          )
    }

    {:ok, state}
  end

  @spec remove_crash_group_if_empty(Pipeline.State.t(), CrashGroup.name_t()) ::
          {:removed | :not_removed, Pipeline.State.t()}
  def remove_crash_group_if_empty(state, group_name) do
    %CrashGroup{alive_members: alive_members} = state.crash_groups[group_name]

    if alive_members == [] do
      state = Bunch.Access.delete_in(state, [:crash_groups, group_name])

      {:removed, state}
    else
      {:not_removed, state}
    end
  end

  @spec remove_member_of_crash_group(Pipeline.State.t(), CrashGroup.name_t(), pid()) ::
          Pipeline.State.t()
  def remove_member_of_crash_group(state, group_name, pid) do
    if group_name in Map.keys(state.crash_groups) do
      Bunch.Access.update_in(
        state,
        [:crash_groups, group_name, :alive_members],
        &List.delete(&1, pid)
      )
      |> Bunch.Access.update_in([:crash_groups, group_name, :dead_members], &[pid | &1])
    else
      state
    end
  end

  @spec get_group_by_member_pid(pid(), Parent.state_t()) :: {:ok, CrashGroup.t()} | :error
  def get_group_by_member_pid(member_pid, state) do
    crash_group =
      state.crash_groups
      |> Map.values()
      |> Enum.find(fn %CrashGroup{alive_members: alive_members_pids} ->
        member_pid in alive_members_pids
      end)

    case crash_group do
      %CrashGroup{} -> {:ok, crash_group}
      nil -> {:error, :not_member}
    end
  end

  @spec set_triggered(Pipeline.State.t(), CrashGroup.name_t(), boolean()) :: Pipeline.State.t()
  def set_triggered(state, group_name, value \\ true) do
    if group_name in Map.keys(state.crash_groups) do
      Bunch.Access.put_in(
        state,
        [:crash_groups, group_name, :triggered?],
        value
      )
    else
      state
    end
  end
end
