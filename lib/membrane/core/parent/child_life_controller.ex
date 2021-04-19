defmodule Membrane.Core.Parent.ChildLifeController do
  @moduledoc false
  use Bunch

  alias __MODULE__.{StartupHandler, LinkHandler, CrashGroupHandler}
  alias Membrane.ParentSpec
  alias Membrane.Core.Parent

  alias Membrane.Core.Parent.{
    ChildEntryParser,
    ClockHandler,
    LifecycleController,
    Link,
    ChildLifeController,
    CrashGroup
  }

  alias Membrane.Core.PlaybackHandler

  require Membrane.Logger
  require Membrane.Bin
  require Membrane.Element

  @spec handle_spec(ParentSpec.t(), Parent.state_t()) ::
          {{:ok, [Membrane.Child.name_t()]}, Parent.state_t()} | no_return
  def handle_spec(%ParentSpec{} = spec, state) do
    Membrane.Logger.debug("""
    Initializing spec
    children: #{inspect(spec.children)}
    links: #{inspect(spec.links)}
    """)

    children = ChildEntryParser.from_spec(spec.children)
    :ok = StartupHandler.check_if_children_names_unique(children, state)
    syncs = StartupHandler.setup_syncs(children, spec.stream_sync)

    children =
      StartupHandler.start_children(
        children,
        state.synchronization.clock_proxy,
        syncs,
        state.children_log_metadata
      )

    # monitoring children
    :ok = children |> Enum.each(&Process.monitor(&1.pid))

    :ok = StartupHandler.maybe_activate_syncs(syncs, state)
    {:ok, state} = StartupHandler.add_children(children, state)
    children_names = children |> Enum.map(& &1.name)

    # adding crash group to state
    {:ok, state} =
      if spec.crash_group do
        children_pids = children |> Enum.map(& &1.pid)
        CrashGroupHandler.add_crash_group(spec.crash_group, children_pids, state)
      else
        {:ok, state}
      end

    state = ClockHandler.choose_clock(children, spec.clock_provider, state)
    {:ok, links} = Link.from_spec(spec.links)
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
        Trying to remove children that are already being removed: #{
          Enum.map_join(already_removing, ", ", &inspect(&1.name))
        }. This may lead to 'unknown child' errors.
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

  If a pid turns out not to be a pid of any child, it is a NOOP.
  """
  @spec maybe_handle_child_death(child_pid :: pid(), reason :: atom(), state :: Parent.state_t()) ::
          {{:ok, :child | :not_child}, Parent.state_t()}
  def maybe_handle_child_death(pid, :normal, state) do
    withl find: {:ok, child_name} <- child_by_pid(pid, state),
          handle: state = Bunch.Access.delete_in(state, [:children, child_name]),
          handle: state = remove_child_links(child_name, state),
          handle: {:ok, state} <- LifecycleController.maybe_finish_playback_transition(state) do
      {{:ok, :child}, state}
    else
      find: :error -> {{:ok, :not_child}, state}
      handle: error -> error
    end
  end

  def maybe_handle_child_death(pid, {:shutdown, :group_kill}, state) do
    withl find: {:ok, _child_name} <- child_by_pid(pid, state),
          find: {:ok, group} <- group_by_member_pid(pid, state) do
      state =
        state
        |> CrashGroupHandler.remove_member_of_crash_group(group.name, pid)
        |> CrashGroupHandler.remove_crash_group_if_empty(group.name)

      {{:ok, :child}, state}
    else
      find: :error -> {{:ok, :not_child}, state}
    end
  end

  def maybe_handle_child_death(pid, _reason, state) do
    withl find: {:ok, group} <- group_by_member_pid(pid, state),
          group_kill: {:ok, state} <- crash_all_group_members(group, state) do
      state =
        state
        |> CrashGroupHandler.remove_member_of_crash_group(group.name, pid)
        |> CrashGroupHandler.remove_crash_group_if_empty(group.name)

      {{:ok, :child}, state}
    else
      find: :error ->
        Membrane.Logger.debug("""
        Pipeline child crashed but was not member of any crash group.
        Terminating.
        """)

        propagate_child_crash()

      group_kill: _error ->
        Membrane.Logger.debug("""
        Error while killing the group.
        """)

        {:error, :can_not_kill_all_group_members}
    end
  end

  # called when process was a member of a crash group
  @spec crash_all_group_members(CrashGroup.t(), Parent.state_t()) :: {:ok, Parent.state_t()}
  defp crash_all_group_members(crash_group, state) do
    %CrashGroup{members: members_pids} = crash_group

    with {:ok, state} <- ChildLifeController.LinkHandler.unlink_crash_group(crash_group, state) do
      :ok =
        Enum.each(
          members_pids,
          fn pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid, {:shutdown, :group_kill})
            end
          end
        )

      {:ok, state}
    end
  end

  # called when a dead child was not a member of any crash group
  defp propagate_child_crash() do
    Membrane.Logger.debug("""
    A child crashed but was not a member of any crash group.
    Terminating.
    """)

    GenServer.stop(self(), :kill)
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

  @spec group_by_member_pid(pid(), Parent.state_t()) :: {:ok, CrashGroup.t()} | :error
  defp group_by_member_pid(member_pid, state) do
    crash_group =
      state.crash_groups
      |> Map.values()
      |> Enum.find(fn %CrashGroup{members: members_pids} ->
        member_pid in members_pids
      end)

    case crash_group do
      %CrashGroup{} -> {:ok, crash_group}
      nil -> :error
    end
  end

  defp child_by_pid(pid, state) do
    case Enum.find(state.children, fn {_name, entry} -> entry.pid == pid end) do
      {child_name, _child_data} -> {:ok, child_name}
      nil -> :error
    end
  end
end
