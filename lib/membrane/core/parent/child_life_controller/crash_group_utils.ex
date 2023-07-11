defmodule Membrane.Core.Parent.ChildLifeController.CrashGroupUtils do
  @moduledoc false
  # A module responsible for managing crash groups inside the state of pipeline.

  alias Membrane.ChildrenSpec
  alias Membrane.Core.{CallbackHandler, Component, Parent, Pipeline}
  alias Membrane.Core.Parent.{ChildLifeController, ChildrenModel, CrashGroup}
  alias Membrane.Core.Parent.ChildLifeController.LinkUtils

  @spec add_crash_group(
          {Membrane.Child.group(), ChildrenSpec.crash_group_mode()},
          [Membrane.Child.name()],
          [pid()],
          Pipeline.State.t()
        ) :: Pipeline.State.t()
  def add_crash_group(group_name, _mode, children, state)
      when is_map_key(state.crash_group, group_name) do
    Bunch.Access.update_in(state, [:crash_groups, group_name, :members], &(children ++ &1))
  end

  def add_crash_group(group_name, mode, children, state) do
    Bunch.Access.put_in(
      state,
      [:crash_groups, group_name],
      %CrashGroup{
        name: group_name,
        mode: mode,
        members: children
      }
    )
  end

  @spec handle_crash_group_member_death(Child.name(), CrashGroup.t(), any(), Parent.state()) ::
          Parent.state()
  def handle_crash_group_member_death(child_name, crash_group_data, reason, state)

  def handle_crash_group_member_death(
        child_name,
        %CrashGroup{triggered?: true} = group,
        _reason,
        state
      ) do
    all_members_dead? =
      Enum.all?(group.members, fn member ->
        member == child_name or not Map.has_key?(state.children, member)
      end)

    if all_members_dead? do
      exec_handle_crash_group_down(group, state)
    else
      state
    end
  end

  def handle_crash_group_member_death(
        child_name,
        %CrashGroup{members: [child_name]} = group,
        :normal,
        state
      ) do
    Bunch.Access.delete_in(state, [:crash_groups, group.name])
  end

  def handle_crash_group_member_death(
        child_name,
        %CrashGroup{members: [child_name]} = group,
        _reason,
        state
      ) do
    state = ChildLifeController.remove_children_from_specs(group.members, state)
    state = LinkUtils.unlink_crash_group(group, state)
    exec_handle_crash_group_down(group, state)
  end

  def handle_crash_group_member_death(child_name, %CrashGroup{} = group, :normal, state) do
    Bunch.Access.update_in(
      state,
      [:crash_groups, group.name, :members],
      &List.delete(&1, child_name)
    )
  end

  def handle_crash_group_member_death(child_name, %CrashGroup{} = group, _reason, state) do
    state = ChildLifeController.remove_children_from_specs(group.members, state)
    state = LinkUtils.unlink_crash_group(group, state)

    Enum.each(group.members, fn child ->
      ChildrenModel.get_child_data!(state, child)
      |> Map.get(:pid)
      |> Process.exit({:shutdown, :membrane_crash_group_kill})
    end)

    Bunch.Access.put_in(state, [:crash_groups, group.name], %CrashGroup{
      group
      | triggered?: true,
        crash_initiator: child_name
    })
  end

  defp exec_handle_crash_group_down(
         crash_group,
         state
       ) do
    context_generator =
      &Component.context_from_state(&1,
        members: crash_group.members,
        crash_initiator: crash_group.crash_initiator
      )

    CallbackHandler.exec_and_handle_callback(
      :handle_crash_group_down,
      Membrane.Core.Pipeline.ActionHandler,
      %{context: context_generator},
      [crash_group.name],
      state
    )
  end
end
