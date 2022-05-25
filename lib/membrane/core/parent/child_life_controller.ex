defmodule Membrane.Core.Parent.ChildLifeController do
  @moduledoc false
  use Bunch

  alias __MODULE__.{CrashGroupHandler, LinkHandler, StartupHandler}
  alias Membrane.ParentSpec
  alias Membrane.Core.{CallbackHandler, Component, Parent, PlaybackHandler}

  alias Membrane.Core.Parent.{
    ChildEntryParser,
    ClockHandler,
    CrashGroup,
    LifecycleController,
    LinkParser
  }

  require Membrane.Core.Component
  require Membrane.Bin
  require Membrane.Element
  require Membrane.Logger

  @type spec_ref_t :: reference()

  @spec handle_spec(ParentSpec.t(), Parent.state_t()) :: Parent.state_t() | no_return()
  def handle_spec(%ParentSpec{} = spec, state) do
    Membrane.Logger.debug("""
    Initializing spec
    children: #{inspect(spec.children)}
    links: #{inspect(spec.links)}
    """)

    {links, children_spec_from_links} = LinkParser.parse(spec.links)
    children_spec = Enum.concat(spec.children, children_spec_from_links)
    children = ChildEntryParser.parse(children_spec)
    spec_ref = make_ref()
    children = Enum.map(children, &%{&1 | spec_ref: spec_ref})
    :ok = StartupHandler.check_if_children_names_unique(children, state)
    syncs = StartupHandler.setup_syncs(children, spec.stream_sync)

    children =
      StartupHandler.start_children(
        children,
        spec.node,
        state.synchronization.clock_proxy,
        syncs,
        spec.log_metadata
      )

    children_names = children |> Enum.map(& &1.name)
    children_pids = children |> Enum.map(& &1.pid)

    # monitoring children
    :ok = Enum.each(children_pids, &Process.monitor(&1))

    :ok = StartupHandler.maybe_activate_syncs(syncs, state)
    state = StartupHandler.add_children(children, state)

    # adding crash group to state
    state =
      if spec.crash_group do
        CrashGroupHandler.add_crash_group(spec.crash_group, children_names, children_pids, state)
      else
        state
      end

    state = ClockHandler.choose_clock(children, spec.clock_provider, state)
    state = LinkHandler.init_spec_linking(spec_ref, links, state)
    StartupHandler.exec_handle_spec_started(children_names, state)
  end

  @spec handle_forward([{Membrane.Child.name_t(), any}], Parent.state_t()) :: :ok
  def handle_forward(children_messages, state) do
    Enum.each(children_messages, &do_handle_forward(&1, state))
  end

  defp do_handle_forward({child_name, message}, state) do
    %{pid: pid} = Parent.ChildrenModel.get_child_data!(state, child_name)
    send(pid, message)
    :ok
  end

  @spec handle_remove_child(Membrane.Child.name_t() | [Membrane.Child.name_t()], Parent.state_t()) ::
          Parent.state_t()
  def handle_remove_child(names, state) do
    names = names |> Bunch.listify()

    {:ok, state} =
      if state.synchronization.clock_provider.provider in names do
        ClockHandler.reset_clock(state)
      else
        {:ok, state}
      end

    data = Enum.map(names, &Parent.ChildrenModel.get_child_data!(state, &1))
    {already_removing, data} = Enum.split_with(data, & &1.terminating?)

    if already_removing != [] do
      Membrane.Logger.warn("""
      Trying to remove children that are already being removed: #{Enum.map_join(already_removing, ", ", &inspect(&1.name))}. This may lead to 'unknown child' errors.
      """)
    end

    Enum.each(data, &PlaybackHandler.request_playback_state_change(&1.pid, :terminating))
    Parent.ChildrenModel.update_children!(state, names, &%{&1 | terminating?: true})
  end

  @spec child_playback_changed(pid, Membrane.PlaybackState.t(), Parent.state_t()) ::
          Parent.state_t()
  def child_playback_changed(pid, child_pb_state, state) do
    {:ok, child} = child_by_pid(pid, state)
    %{playback: playback} = state

    cond do
      playback.pending_state == nil and playback.state == child_pb_state ->
        put_in(state, [:children, child, :playback_sync], :synced)

      playback.pending_state == child_pb_state ->
        state = put_in(state, [:children, child, :playback_sync], :synced)
        LifecycleController.maybe_finish_playback_transition(state)

      true ->
        state
    end
  end

  @doc """
  Handles death of a child:
  - removes it from state
  - if in playback transition, checks if it can be finished (in case the dead child
    was the last one we were waiting for to change the playback state)

  If a pid turns out not to be a pid of any child error is raised.
  """
  @spec handle_child_death(child_pid :: pid(), reason :: any(), state :: Parent.state_t()) ::
          Parent.state_t()
  def handle_child_death(pid, :normal, state) do
    with {:ok, child_name} <- child_by_pid(pid, state) do
      state = Bunch.Access.delete_in(state, [:children, child_name])
      state = LinkHandler.unlink_element(child_name, state)
      {_result, state} = remove_child_from_crash_group(state, pid)
      LifecycleController.maybe_finish_playback_transition(state)
    else
      {:error, :not_child} ->
        raise Membrane.PipelineError,
              "Tried to handle death of process that wasn't a child of that pipeline."
    end
  end

  def handle_child_death(pid, reason, state) do
    with {:ok, group} <- CrashGroupHandler.get_group_by_member_pid(pid, state),
         {:ok, child_name} <- child_by_pid(pid, state) do
      {result, state} =
        crash_all_group_members(group, child_name, state)
        |> remove_child_from_crash_group(group, pid)

      if result == :removed do
        state = Enum.reduce(group.members, state, &Bunch.Access.delete_in(&2, [:children, &1]))

        exec_handle_crash_group_down_callback(
          group.name,
          group.members,
          group.crash_initiator || child_name,
          state
        )
      else
        state
      end
    else
      {:error, :not_child} ->
        raise Membrane.PipelineError,
              "Tried to handle death of process that wasn't a child of that pipeline."

      {:error, :not_member} when reason == {:shutdown, :membrane_crash_group_kill} ->
        raise Membrane.PipelineError,
              "Child that was not a member of any crash group killed with :membrane_crash_group_kill."

      {:error, :not_member} ->
        Membrane.Logger.debug("""
        Pipeline child crashed but was not a member of any crash group.
        Terminating.
        """)

        propagate_child_crash()
        state
    end
  end

  defp exec_handle_crash_group_down_callback(
         group_name,
         group_members,
         crash_initiator,
         state
       ) do
    context =
      Component.callback_context_generator(:parent, CrashGroupDown, state,
        members: group_members,
        crash_initiator: crash_initiator
      )

    CallbackHandler.exec_and_handle_callback(
      :handle_crash_group_down,
      Membrane.Core.Pipeline.ActionHandler,
      %{context: context},
      [group_name],
      state
    )
  end

  # called when process was a member of a crash group
  @spec crash_all_group_members(CrashGroup.t(), Membrane.Child.name_t(), Parent.state_t()) ::
          Parent.state_t()
  defp crash_all_group_members(
         %CrashGroup{triggered?: false} = crash_group,
         crash_initiator,
         state
       ) do
    %CrashGroup{alive_members_pids: members_pids} = crash_group

    state = LinkHandler.unlink_crash_group(crash_group, state)

    Enum.each(
      members_pids,
      fn pid ->
        if node(pid) == node() do
          if Process.alive?(pid),
            do: GenServer.stop(pid, {:shutdown, :membrane_crash_group_kill})
        else
          if :rpc.call(node(pid), Process, :alive?, [pid]),
            do: GenServer.stop(pid, {:shutdown, :membrane_crash_group_kill})
        end
      end
    )

    CrashGroupHandler.set_triggered(state, crash_group.name, crash_initiator)
  end

  defp crash_all_group_members(_crash_group, _crash_initiator, state), do: state

  # called when a dead child was not a member of any crash group
  defp propagate_child_crash() do
    Membrane.Logger.debug("""
    A child crashed but was not a member of any crash group.
    Terminating.
    """)

    Process.flag(:trap_exit, false)
    Process.exit(self(), {:shutdown, :child_crash})
  end

  defp remove_child_from_crash_group(state, child_pid) do
    with {:ok, group} <- CrashGroupHandler.get_group_by_member_pid(child_pid, state) do
      remove_child_from_crash_group(state, group, child_pid)
    else
      {:error, :not_member} -> {:not_removed, state}
    end
  end

  defp remove_child_from_crash_group(state, group, child_pid) do
    CrashGroupHandler.remove_member_of_crash_group(state, group.name, child_pid)
    |> CrashGroupHandler.remove_crash_group_if_empty(group.name)
  end

  defp child_by_pid(pid, state) do
    case Enum.find(state.children, fn {_name, entry} -> entry.pid == pid end) do
      {child_name, _child_data} -> {:ok, child_name}
      nil -> {:error, :not_child}
    end
  end
end
