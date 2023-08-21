defmodule Membrane.Core.Parent.ChildLifeController.CrashGroupUtils do
  @moduledoc false
  # A module responsible for managing crash groups inside the state of pipeline.

  alias Membrane.{Child, ChildrenSpec}
  alias Membrane.Core.{CallbackHandler, Component, Parent}
  alias Membrane.Core.Parent.{ChildLifeController, ChildrenModel, CrashGroup}
  alias Membrane.Core.Parent.ChildLifeController.LinkUtils

  @spec add_crash_group(
          Child.group(),
          ChildrenSpec.crash_group_mode(),
          [Child.name()],
          Parent.state()
        ) :: Parent.state()
  def add_crash_group(group_name, mode, children, state)
      when not is_map_key(state.crash_groups, group_name) do
    put_in(
      state,
      [:crash_groups, group_name],
      %CrashGroup{
        name: group_name,
        mode: mode,
        members: children
      }
    )
  end

  @spec extend_crash_group(
          Child.group(),
          ChildrenSpec.crash_group_mode(),
          [Child.name()],
          Parent.state()
        ) :: Parent.state()
  def extend_crash_group(group_name, _mode, children, state) do
    update_in(state, [:crash_groups, group_name, :members], &(children ++ &1))
  end

  @spec get_child_crash_group(Child.name(), Parent.state()) :: {:ok, CrashGroup.t()} | :error
  def get_child_crash_group(child_name, state) do
    %{group: group_name} = ChildrenModel.get_child_data!(state, child_name)
    Map.fetch(state.crash_groups, group_name)
  end

  @spec handle_crash_group_member_death(Child.name(), CrashGroup.t(), any(), Parent.state()) ::
          Parent.state()
  def handle_crash_group_member_death(child_name, %CrashGroup{} = group, :normal, state) do
    # if a child dies with reason :normal, there will be no need to kill it during crash group detonation
    # and we will not want to have it in :crash_group_members in the callback context in handle_crash_group_down/3,
    # so this child is removed from :members in crash group struct
    members = List.delete(group.members, child_name)
    state = put_in(state, [:crash_groups, group.name, :members], members)

    if group.detonating? and Enum.all?(members, &(not Map.has_key?(state.children, &1))) do
      cleanup_crash_group(group.name, state)
    else
      state
    end
  end

  def handle_crash_group_member_death(child_name, %CrashGroup{} = group, _reason, state) do
    state =
      if group.detonating? do
        state
      else
        detonate_crash_group(child_name, group, state)
      end

    all_members_dead? =
      List.delete(group.members, child_name)
      |> Enum.all?(&(not Map.has_key?(state.children, &1)))

    if all_members_dead? do
      cleanup_crash_group(group.name, state)
    else
      state
    end
  end

  defp detonate_crash_group(crash_initiator, %CrashGroup{} = group, state) do
    state = ChildLifeController.remove_children_from_specs(group.members, state)
    state = LinkUtils.unlink_crash_group(group, state)

    List.delete(group.members, crash_initiator)
    |> Enum.each(fn group_member ->
      get_in(state, [:children, group_member, :pid])
      |> Process.exit({:shutdown, :membrane_crash_group_kill})
    end)

    update_in(
      state,
      [:crash_groups, group.name],
      &%CrashGroup{
        &1
        | detonating?: true,
          crash_initiator: crash_initiator
      }
    )
  end

  defp cleanup_crash_group(group_name, state) do
    state = exec_handle_crash_group_down(group_name, state)
    {_group, state} = pop_in(state, [:crash_groups, group_name])
    state
  end

  defp exec_handle_crash_group_down(
         group_name,
         state
       ) do
    crash_group = get_in(state, [:crash_groups, group_name])

    context_generator =
      &Component.context_from_state(&1,
        members: crash_group.members,
        crash_initiator: crash_group.crash_initiator
      )

    CallbackHandler.exec_and_handle_callback(
      :handle_crash_group_down,
      Component.action_handler(state),
      %{context: context_generator},
      [crash_group.name],
      state
    )
  end
end
