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
    Link,
    LinkParser
  }

  require Membrane.Core.Component
  require Membrane.Bin
  require Membrane.Element
  require Membrane.Logger

  @spec handle_spec(ParentSpec.t(), Parent.state_t()) ::
          {{:ok, [Membrane.Child.name_t()]}, Parent.state_t()} | no_return
  def handle_spec(%ParentSpec{} = spec, state) do
    Membrane.Logger.debug("""
    Initializing spec
    children: #{inspect(spec.children)}
    links: #{inspect(spec.links)}
    """)

    {links, children_spec_from_links} = LinkParser.parse(spec.links)
    children_spec = Enum.concat(spec.children, children_spec_from_links)
    children = ChildEntryParser.parse(children_spec)
    :ok = StartupHandler.check_if_children_names_unique(children, state)
    syncs = StartupHandler.setup_syncs(children, spec.stream_sync)

    # ensure node is set to local if it's nil in spec
    node = spec.node || node()

    children =
      StartupHandler.start_children(
        children,
        node,
        state.synchronization.clock_proxy,
        syncs,
        state.children_log_metadata
      )

    children_names = children |> Enum.map(& &1.name)
    children_pids = children |> Enum.map(& &1.pid)

    # monitoring children
    :ok = Enum.each(children_pids, &Process.monitor(&1))

    :ok = StartupHandler.maybe_activate_syncs(syncs, state)
    {:ok, state} = StartupHandler.add_children(children, state)

    # adding crash group to state
    {:ok, state} =
      if spec.crash_group do
        CrashGroupHandler.add_crash_group(spec.crash_group, children_names, children_pids, state)
      else
        {:ok, state}
      end

    state = ClockHandler.choose_clock(children, spec.clock_provider, state)
    links = LinkHandler.resolve_links(links, state)
    {:ok, state} = LinkHandler.link_children(links, state)
    {:ok, state} = StartupHandler.exec_handle_spec_started(children_names, state)
    state = StartupHandler.init_playback_state(children_names, state)

    {{:ok, children_names}, state}
  end

  @spec handle_forward([{Membrane.Child.name_t(), any}], Parent.state_t()) ::
          {:ok | {:error, any}, Parent.state_t()}
  def handle_forward(children_messages, state) do
    result = Bunch.Enum.try_each(children_messages, &do_handle_forward(&1, state))
    {result, state}
  end

  defp do_handle_forward({child_name, message}, state) do
    with {:ok, %{pid: pid}} <- state |> Parent.ChildrenModel.get_child_data(child_name) do
      send(pid, message)
      :ok
    else
      {:error, reason} ->
        {:error, {:cannot_forward_message, [element: child_name, message: message], reason}}
    end
  end

  @spec handle_remove_child(Membrane.Child.name_t() | [Membrane.Child.name_t()], Parent.state_t()) ::
          {:ok | {:error, any}, Parent.state_t()}
  def handle_remove_child(names, state) do
    names = names |> Bunch.listify()

    {:ok, state} =
      if state.synchronization.clock_provider.provider in names do
        ClockHandler.reset_clock(state)
      else
        {:ok, state}
      end

    with {:ok, data} <- Bunch.Enum.try_map(names, &Parent.ChildrenModel.get_child_data(state, &1)) do
      {already_removing, data} = Enum.split_with(data, & &1.terminating?)

      if already_removing != [] do
        Membrane.Logger.warn("""
        Trying to remove children that are already being removed: #{Enum.map_join(already_removing, ", ", &inspect(&1.name))}. This may lead to 'unknown child' errors.
        """)
      end

      data |> Enum.each(&PlaybackHandler.request_playback_state_change(&1.pid, :terminating))

      {:ok, state} =
        Parent.ChildrenModel.update_children(state, names, &%{&1 | terminating?: true})

      {:ok, state}
    else
      error -> {error, state}
    end
  end

  @spec child_playback_changed(pid, Membrane.PlaybackState.t(), Parent.state_t()) ::
          {:ok | {:error, any}, Parent.state_t()}
  def child_playback_changed(pid, child_pb_state, state) do
    {:ok, child} = child_by_pid(pid, state)
    %{playback: playback} = state

    cond do
      playback.pending_state == nil and playback.state == child_pb_state ->
        state = put_in(state, [:children, child, :playback_synced?], true)
        {:ok, state}

      playback.pending_state == child_pb_state ->
        state = put_in(state, [:children, child, :playback_synced?], true)
        LifecycleController.maybe_finish_playback_transition(state)

      true ->
        {:ok, state}
    end
  end

  @doc """
  Handles death of a child:
  - removes it from state
  - if in playback transition, checks if it can be finished (in case the dead child
    was the last one we were waiting for to change the playback state)

  If a pid turns out not to be a pid of any child error is raised.
  """
  @spec handle_child_death(child_pid :: pid(), reason :: atom(), state :: Parent.state_t()) ::
          {:ok | {:error, :not_child}, Parent.state_t()}
  def handle_child_death(pid, :normal, state) do
    with {:ok, child_name} <- child_by_pid(pid, state) do
      state = Bunch.Access.delete_in(state, [:children, child_name])
      state = remove_child_links(child_name, state)
      {_result, state} = remove_child_from_crash_group(state, pid)
      LifecycleController.maybe_finish_playback_transition(state)
    else
      {:error, :not_child} ->
        raise Membrane.PipelineError,
              "Tried to handle death of process that wasn't a child of that pipeline."
    end
  end

  def handle_child_death(pid, reason, state) do
    with {:ok, group} <- CrashGroupHandler.get_group_by_member_pid(pid, state) do
      {result, state} =
        crash_all_group_members(group, state)
        |> remove_child_from_crash_group(group, pid)

      if result == :removed do
        state = Enum.reduce(group.members, state, &Bunch.Access.delete_in(&2, [:children, &1]))
        exec_handle_crash_group_down_callback(group.name, group.members, state)
      else
        {:ok, state}
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

        propagate_child_crash(state)
    end
  end

  defp exec_handle_crash_group_down_callback(group_name, group_members, state) do
    context =
      Component.callback_context_generator(:parent, CrashGroupDown, state, members: group_members)

    CallbackHandler.exec_and_handle_callback(
      :handle_crash_group_down,
      Membrane.Core.Pipeline.ActionHandler,
      %{context: context},
      [group_name],
      state
    )
  end

  # called when process was a member of a crash group
  @spec crash_all_group_members(CrashGroup.t(), Parent.state_t()) :: Parent.state_t()
  defp crash_all_group_members(%CrashGroup{triggered?: false} = crash_group, state) do
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

    CrashGroupHandler.set_triggered(state, crash_group.name)
  end

  defp crash_all_group_members(_crash_group, state), do: state

  # called when a dead child was not a member of any crash group
  defp propagate_child_crash(state) do
    Membrane.Logger.debug("""
    A child crashed but was not a member of any crash group.
    Terminating.
    """)

    {:stop, {:shutdown, :child_crash}, state}
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

  defp remove_child_links(child_name, state) do
    Map.update!(
      state,
      :links,
      &(&1
        |> Enum.reject(fn %Link{from: from, to: to} ->
          %Link.Endpoint{child: from_name} = from
          %Link.Endpoint{child: to_name} = to

          from_name == child_name or to_name == child_name
        end))
    )
  end

  defp child_by_pid(pid, state) do
    case Enum.find(state.children, fn {_name, entry} -> entry.pid == pid end) do
      {child_name, _child_data} -> {:ok, child_name}
      nil -> {:error, :not_child}
    end
  end
end
