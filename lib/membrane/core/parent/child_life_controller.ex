defmodule Membrane.Core.Parent.ChildLifeController do
  @moduledoc false
  use Bunch

  alias __MODULE__.{CrashGroupUtils, LinkUtils, StartupUtils}
  alias Membrane.ParentSpec
  alias Membrane.Core.{Bin, CallbackHandler, Component, Parent, Pipeline}

  alias Membrane.Core.Parent.{
    ChildEntryParser,
    ChildrenModel,
    ClockHandler,
    CrashGroup,
    Link,
    LinkParser
  }

  require Membrane.Core.Component
  require Membrane.Core.Message, as: Message
  require Membrane.Logger

  @type spec_ref_t :: reference()

  @type pending_spec_t :: %{
          status: :linking_internally | :linked_internally | :linking_externally | :ready,
          children_names: [Membrane.Child.name_t()],
          links_ids: [Link.id()],
          awaiting_responses: %{Link.id() => 0..2},
          dependent_specs: MapSet.t(spec_ref_t),
          links: %{
            Link.id() => %{link: Link.t(), awaiting_responses: non_neg_integer()}
          }
        }

  @type pending_specs_t :: %{spec_ref_t() => pending_spec_t()}

  @doc """
  Handles `Membrane.ParentSpec` returned with `spec` action.

  Handling a spec consists of the following steps:
  - Parse the spec
  - Set up `Membrane.Sync`s
  - Spawn children processes. If any process crashes when being spawned (that is in `handle_init`),
    the parent is terminated.
  - Activate syncs and choose clock
  - Set spec status to `:initializing` and store the spec in `pending_specs` in state. It's kept there
    until the spec is fully handled. If any child of the spec that is in a crash group crashes by then,
    the spawning of the spec is cancelled and spec is cleaned up. That's possible because only one crash
    group per spec is allowed.
  - Optionally add crash group
  - Execute `handle_spec_startup` callback
  - Wait until all children are initialized and all dependent specs are fully handled. Dependent specs are
    those containing children that are linked in the current spec.
  - Set spec status to `:initialized`
  - Send link requests for all the links in the spec. Set spec status to `:linking_internally`. Wait until
    all link responses are received.
  - Link all links that are not involving bin pads.
  - If the parent is bin, send link responses for bin pads, set spec status to `:linking_externally` and wait
    until all bin pads of the spec are linked. Linking bin pads is actually routing link calls to proper
    bin children.
  - Mark spec children as ready, optionally request to play or terminate
  - Cleanup spec: remove it from `pending_specs` and all other specs' `dependent_specs` and try proceeding startup
    for all other pending specs that depended on the spec.
  """
  @spec handle_spec(ParentSpec.t(), Parent.state_t()) :: Parent.state_t() | no_return()
  def handle_spec(%ParentSpec{} = spec, state) do
    spec_ref = make_ref()

    Membrane.Logger.debug("""
    New spec #{inspect(spec_ref)}
    children: #{inspect(spec.children)}
    links: #{inspect(spec.links)}
    """)

    {links, children_spec_from_links} = LinkParser.parse(spec.links)
    children_spec = Enum.concat(spec.children, children_spec_from_links)
    children = ChildEntryParser.parse(children_spec)
    children = Enum.map(children, &%{&1 | spec_ref: spec_ref})
    :ok = StartupUtils.check_if_children_names_unique(children, state)
    syncs = StartupUtils.setup_syncs(children, spec.stream_sync)

    log_metadata =
      case state do
        %Bin.State{children_log_metadata: metadata} -> metadata ++ spec.log_metadata
        %Pipeline.State{} -> spec.log_metadata
      end

    children =
      StartupUtils.start_children(
        children,
        spec.node,
        state.synchronization.clock_proxy,
        syncs,
        log_metadata,
        state.children_supervisor
      )

    children_names = children |> Enum.map(& &1.name)
    children_pids = children |> Enum.map(& &1.pid)

    :ok = StartupUtils.maybe_activate_syncs(syncs, state)
    state = ClockHandler.choose_clock(children, spec.clock_provider, state)
    state = %{state | children: Map.merge(state.children, Map.new(children, &{&1.name, &1}))}
    links = LinkUtils.resolve_links(links, spec_ref, state)
    state = %{state | links: Map.merge(state.links, Map.new(links, &{&1.id, &1}))}

    dependent_specs =
      links
      |> Enum.flat_map(&[&1.from.child_spec_ref, &1.to.child_spec_ref])
      |> Enum.filter(&Map.has_key?(state.pending_specs, &1))
      |> MapSet.new()

    state =
      put_in(state, [:pending_specs, spec_ref], %{
        status: :initializing,
        children_names: children_names,
        links_ids: Enum.map(links, & &1.id),
        dependent_specs: dependent_specs,
        awaiting_responses: []
      })

    # adding crash group to state
    state =
      if spec.crash_group do
        CrashGroupUtils.add_crash_group(spec.crash_group, children_names, children_pids, state)
      else
        state
      end

    state = StartupUtils.exec_handle_spec_started(children_names, state)
    proceed_spec_startup(spec_ref, state)
  end

  @spec handle_spec_timeout(spec_ref_t(), Parent.state_t()) ::
          Parent.state_t()
  def handle_spec_timeout(spec_ref, state) do
    {spec_data, state} = pop_in(state, [:pending_specs, spec_ref])

    unless spec_data == nil or spec_data.status == :ready do
      raise Membrane.LinkError,
            "Spec #{inspect(spec_ref)} linking took too long, spec_data: #{inspect(spec_data, pretty: true)}"
    end

    state
  end

  @spec proceed_spec_startup(spec_ref_t(), Parent.state_t()) ::
          Parent.state_t()
  def proceed_spec_startup(spec_ref, state) do
    withl spec_data: {:ok, spec_data} <- Map.fetch(state.pending_specs, spec_ref),
          do: {spec_data, state} = do_proceed_spec_startup(spec_ref, spec_data, state),
          status: :ready <- spec_data.status do
      cleanup_spec_startup(spec_ref, state)
    else
      spec_data: :error -> state
      status: _status -> put_in(state, [:pending_specs, spec_ref], spec_data)
    end
  end

  defp do_proceed_spec_startup(spec_ref, %{status: :initializing} = spec_data, state) do
    Membrane.Logger.debug(
      "Proceeding spec #{inspect(spec_ref)} startup: initializing, dependent specs: #{inspect(spec_data.dependent_specs)}"
    )

    %{children: children} = state

    if Enum.all?(spec_data.children_names, &Map.fetch!(children, &1).initialized?) and
         Enum.empty?(spec_data.dependent_specs) do
      Membrane.Logger.debug("Spec #{inspect(spec_ref)} status changed to initialized")
      do_proceed_spec_startup(spec_ref, %{spec_data | status: :initialized}, state)
    else
      {spec_data, state}
    end
  end

  defp do_proceed_spec_startup(spec_ref, %{status: :initialized} = spec_data, state) do
    Process.send_after(self(), Message.new(:spec_linking_timeout, spec_ref), 5000)

    {awaiting_responses, state} =
      Enum.map_reduce(spec_data.links_ids, state, fn link_id, state ->
        %Membrane.Core.Parent.Link{from: from, to: to, spec_ref: spec_ref} =
          Map.fetch!(state.links, link_id)

        {awaiting_responses_from, state} =
          LinkUtils.request_link(:output, from, to, spec_ref, link_id, state)

        {awaiting_responses_to, state} =
          LinkUtils.request_link(:input, to, from, spec_ref, link_id, state)

        {{link_id, awaiting_responses_from + awaiting_responses_to}, state}
      end)

    spec_data = %{
      spec_data
      | awaiting_responses: Map.new(awaiting_responses),
        status: :linking_internally
    }

    Membrane.Logger.debug("Spec #{inspect(spec_ref)} status changed to linking internally")
    do_proceed_spec_startup(spec_ref, spec_data, state)
  end

  defp do_proceed_spec_startup(spec_ref, %{status: :linking_internally} = spec_data, state) do
    if spec_data.awaiting_responses |> Map.values() |> Enum.all?(&(&1 == 0)) do
      state =
        spec_data.links_ids
        |> Enum.map(&Map.fetch!(state.links, &1))
        |> Enum.reduce(state, &LinkUtils.link/2)

      Membrane.Logger.debug("Spec #{inspect(spec_ref)} status changed to linked internally")
      do_proceed_spec_startup(spec_ref, %{spec_data | status: :linked_internally}, state)
    else
      {spec_data, state}
    end
  end

  defp do_proceed_spec_startup(
         spec_ref,
         %{status: :linked_internally} = spec_data,
         %Pipeline.State{} = state
       ) do
    Membrane.Logger.debug("Spec #{inspect(spec_ref)} status changed to ready")
    do_proceed_spec_startup(spec_ref, %{spec_data | status: :ready}, state)
  end

  defp do_proceed_spec_startup(
         spec_ref,
         %{status: :linked_internally} = spec_data,
         %Bin.State{} = state
       ) do
    state = Bin.PadController.respond_links(spec_ref, state)
    Membrane.Logger.debug("Spec #{inspect(spec_ref)} status changed to linking externally")
    do_proceed_spec_startup(spec_ref, %{spec_data | status: :linking_externally}, state)
  end

  defp do_proceed_spec_startup(
         spec_ref,
         %{status: :linking_externally} = spec_data,
         %Bin.State{} = state
       ) do
    if Bin.PadController.all_pads_linked?(spec_ref, state) do
      Membrane.Logger.debug("Spec #{inspect(spec_ref)} status changed to ready")
      do_proceed_spec_startup(spec_ref, %{spec_data | status: :ready}, state)
    else
      {spec_data, state}
    end
  end

  defp do_proceed_spec_startup(_spec_ref, %{status: :ready} = spec_data, state) do
    state =
      Enum.reduce(spec_data.children_names, state, fn child, state ->
        %{pid: pid, terminating?: terminating?} = get_in(state, [:children, child])

        cond do
          terminating? -> Message.send(pid, :terminate)
          state.playback == :playing -> Message.send(pid, :play)
          true -> :ok
        end

        put_in(state, [:children, child, :ready?], true)
      end)

    {spec_data, state}
  end

  @spec handle_link_response(Parent.Link.id(), Parent.state_t()) :: Parent.state_t()
  def handle_link_response(link_id, state) do
    case Map.fetch(state.links, link_id) do
      {:ok, %Link{spec_ref: spec_ref}} ->
        state =
          update_in(
            state,
            [:pending_specs, spec_ref, :awaiting_responses, link_id],
            &(&1 - 1)
          )

        proceed_spec_startup(spec_ref, state)

      :error ->
        state
    end
  end

  @spec handle_child_initialized(Membrane.Child.name_t(), Parent.state_t()) :: Parent.state_t()
  def handle_child_initialized(child, state) do
    %{spec_ref: spec_ref} = Parent.ChildrenModel.get_child_data!(state, child)
    state = put_in(state, [:children, child, :initialized?], true)
    proceed_spec_startup(spec_ref, state)
  end

  @spec handle_notify_child(
          {Membrane.Child.name_t(), Membrane.ParentNotification.t()},
          Parent.state_t()
        ) :: :ok
  def handle_notify_child({child_name, message}, state) do
    %{pid: pid} = Parent.ChildrenModel.get_child_data!(state, child_name)
    Membrane.Core.Message.send(pid, :parent_notification, [message])
    :ok
  end

  @spec handle_remove_children(
          Membrane.Child.name_t() | [Membrane.Child.name_t()],
          Parent.state_t()
        ) ::
          Parent.state_t()
  def handle_remove_children(names, state) do
    names = names |> Bunch.listify()

    state =
      if state.synchronization.clock_provider.provider in names do
        ClockHandler.reset_clock(state)
      else
        state
      end

    data = Enum.map(names, &Parent.ChildrenModel.get_child_data!(state, &1))
    {already_removing, data} = Enum.split_with(data, & &1.terminating?)

    if already_removing != [] do
      Membrane.Logger.warn("""
      Trying to remove children that are already being removed: #{Enum.map_join(already_removing, ", ", &inspect(&1.name))}. This may lead to 'unknown child' errors.
      """)
    end

    data |> Enum.filter(& &1.ready?) |> Enum.each(&Message.send(&1.pid, :terminate))
    Parent.ChildrenModel.update_children!(state, names, &%{&1 | terminating?: true})
  end

  @doc """
  Handles death of a child:
  - removes it from state
  - unlinks it from other children
  - handles crash group (if applicable)
  """
  @spec handle_child_death(child_pid :: pid(), reason :: any(), state :: Parent.state_t()) ::
          {:stop | :continue, Parent.state_t()}
  def handle_child_death(child_name, reason, state) do
    state = do_handle_child_death(child_name, reason, state)

    if state.terminating? and Enum.empty?(state.children) do
      {:stop, state}
    else
      {:continue, state}
    end
  end

  defp do_handle_child_death(child_name, :normal, state) do
    {%{pid: child_pid}, state} = Bunch.Access.pop_in(state, [:children, child_name])
    state = LinkUtils.unlink_element(child_name, state)
    {_result, state} = remove_child_from_crash_group(state, child_pid)
    state
  end

  defp do_handle_child_death(child_name, reason, state) do
    %{pid: child_pid} = ChildrenModel.get_child_data!(state, child_name)

    with {:ok, group} <- CrashGroupUtils.get_group_by_member_pid(child_pid, state) do
      {result, state} =
        crash_all_group_members(group, child_name, state)
        |> remove_child_from_crash_group(group, child_pid)

      if result == :removed do
        state =
          Enum.reduce(group.members, state, fn child_name, state ->
            {%{spec_ref: spec_ref}, state} = Bunch.Access.pop_in(state, [:children, child_name])
            state = LinkUtils.unlink_element(child_name, state)
            cleanup_spec_startup(spec_ref, state)
          end)

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
      {:error, :not_member} when reason == {:shutdown, :membrane_crash_group_kill} ->
        raise Membrane.PipelineError,
              "Child #{inspect(child_name)} that was not a member of any crash group killed with :membrane_crash_group_kill."

      {:error, :not_member} ->
        Membrane.Logger.debug("""
        Child #{inspect(child_name)} crashed but was not a member of any crash group.
        Terminating.
        """)

        exit({:shutdown, :child_crash})
    end
  end

  defp cleanup_spec_startup(spec_ref, state) do
    if Map.has_key?(state.pending_specs, spec_ref) do
      Membrane.Logger.debug("Cleaning spec #{inspect(spec_ref)}")

      pending_specs =
        state.pending_specs
        |> Map.delete(spec_ref)
        |> Map.new(fn {ref, data} ->
          {ref, Map.update!(data, :dependent_specs, &MapSet.delete(&1, spec_ref))}
        end)

      state = %{state | pending_specs: pending_specs}
      Enum.reduce(Map.keys(pending_specs), state, &proceed_spec_startup/2)
    else
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
    state = LinkUtils.unlink_crash_group(crash_group, state)
    Enum.each(members_pids, &Process.exit(&1, {:shutdown, :membrane_crash_group_kill}))
    CrashGroupUtils.set_triggered(state, crash_group.name, crash_initiator)
  end

  defp crash_all_group_members(_crash_group, _crash_initiator, state), do: state

  defp remove_child_from_crash_group(state, child_pid) do
    with {:ok, group} <- CrashGroupUtils.get_group_by_member_pid(child_pid, state) do
      remove_child_from_crash_group(state, group, child_pid)
    else
      {:error, :not_member} -> {:not_removed, state}
    end
  end

  defp remove_child_from_crash_group(state, group, child_pid) do
    CrashGroupUtils.remove_member_of_crash_group(state, group.name, child_pid)
    |> CrashGroupUtils.remove_crash_group_if_empty(group.name)
  end
end
