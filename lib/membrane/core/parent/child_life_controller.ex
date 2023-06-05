defmodule Membrane.Core.Parent.ChildLifeController do
  @moduledoc false
  use Bunch

  alias __MODULE__.{CrashGroupUtils, LinkUtils, StartupUtils}
  alias Membrane.{Child, ChildrenSpec}
  alias Membrane.Core.{Bin, CallbackHandler, Component, Parent, Pipeline}

  alias Membrane.Core.Parent.{
    ChildEntryParser,
    ChildrenModel,
    ClockHandler,
    CrashGroup,
    Link,
    SpecificationParser
  }

  alias Membrane.Pad
  alias Membrane.ParentError

  require Membrane.Core.Component
  require Membrane.Core.Message, as: Message
  require Membrane.Logger

  @type spec_ref :: reference()

  @type pending_spec :: %{
          status:
            :initializing
            | :linking_internally
            | :linked_internally
            | :linking_externally
            | :ready,
          children_names: MapSet.t(Child.name()),
          links_ids: [Link.id()],
          awaiting_responses: MapSet.t({Link.id(), Membrane.Pad.direction()}),
          dependent_specs: MapSet.t(spec_ref())
        }

  @type pending_specs :: %{spec_ref() => pending_spec()}

  @opaque parsed_children_spec_options :: %{
            group: Child.group(),
            crash_group_mode: ChildrenSpec.crash_group_mode(),
            stream_sync: :sinks | [[Child.name()]],
            clock_provider: Child.name() | nil,
            node: node() | nil,
            log_metadata: Keyword.t()
          }

  @type children_spec_canonical_form :: [
          {[ChildrenSpec.builder()], parsed_children_spec_options()}
        ]

  @spec_dependency_requiring_statuses [:initializing, :linking_internally]

  @children_spec_options_fields_specs [
    group: [require?: false],
    crash_group_mode: [require?: false],
    crash_group: [require?: false],
    stream_sync: [require?: false],
    clock_provider: [require?: false],
    node: [require?: false],
    log_metadata: [require?: false]
  ]

  @default_children_spec_options %{
    group: nil,
    crash_group_mode: nil,
    stream_sync: [],
    clock_provider: nil,
    node: nil,
    log_metadata: []
  }

  @doc """
  Handles `Membrane.ChildrenSpec` returned with `spec` action.

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
  @spec handle_spec(ChildrenSpec.t(), Parent.state()) :: Parent.state() | no_return()
  def handle_spec(spec, state) do
    spec_ref = make_ref()
    canonical_spec = make_canonical(spec)

    Membrane.Logger.debug("""
    New spec with ref: #{inspect(spec_ref)}
    specification: #{inspect(spec)}
    """)

    parsed_specifications =
      Enum.map(canonical_spec, fn {specifications, options} ->
        {this_specifications_children_definitions, this_specifications_links} =
          SpecificationParser.parse(specifications)

        {this_specifications_children_definitions, this_specifications_links, options}
      end)

    children_definitions =
      Enum.map(parsed_specifications, fn {children_definitions, _links, options} ->
        {children_definitions, options}
      end)
      |> Enum.filter(fn {children_definitions, _options} -> children_definitions != [] end)

    StartupUtils.check_if_children_names_and_children_groups_ids_are_unique(
      children_definitions,
      state
    )

    children_definitions = remove_unecessary_children_specs(children_definitions, state)

    links =
      Enum.flat_map(parsed_specifications, fn {_children, links, _options} ->
        links
      end)

    :ok = assert_all_static_pads_linked_in_spec!(children_definitions, links)

    {all_children_names, state} =
      Enum.flat_map_reduce(children_definitions, state, &setup_children(&1, spec_ref, &2))

    resolved_links = LinkUtils.resolve_links(links, spec_ref, state)
    state = %{state | links: Map.merge(state.links, Map.new(resolved_links, &{&1.id, &1}))}

    dependent_specs =
      resolved_links
      |> Enum.flat_map(&[&1.from.child_spec_ref, &1.to.child_spec_ref])
      |> Enum.uniq()
      |> Enum.filter(fn spec_ref ->
        get_in(state, [:pending_specs, spec_ref, :status]) in @spec_dependency_requiring_statuses
      end)
      |> MapSet.new()

    state =
      put_in(state, [:pending_specs, spec_ref], %{
        status: :initializing,
        children_names: MapSet.new(all_children_names),
        links_ids: Enum.map(links, & &1.id),
        dependent_specs: dependent_specs,
        awaiting_responses: MapSet.new()
      })

    state = StartupUtils.exec_handle_spec_started(all_children_names, state)
    proceed_spec_startup(spec_ref, state)
  end

  defp assert_all_static_pads_linked_in_spec!(children_definitions, links) do
    pads_to_link =
      links
      |> Enum.flat_map(&[&1.from, &1.to])
      |> MapSet.new(&{&1.child, &1.pad_spec})

    children_definitions
    |> Enum.flat_map(fn {definitions, _options} -> definitions end)
    |> Enum.flat_map(fn {child_name, child_definition, _opts} ->
      child_module =
        case child_definition do
          %module{} -> module
          module when is_atom(module) -> module
        end

      child_module.membrane_pads()
      |> Keyword.values()
      |> Enum.filter(&(&1.availability == :always))
      |> Enum.map(&{child_name, &1.name})
    end)
    |> Enum.find(&(not MapSet.member?(pads_to_link, &1)))
    |> case do
      {child_name, pad_name} ->
        raise ParentError,
              "Child #{inspect(child_name)} has static pad #{inspect(pad_name)}, but it is not linked in spec"

      nil ->
        :ok
    end
  end

  @spec make_canonical(ChildrenSpec.t(), parsed_children_spec_options()) ::
          children_spec_canonical_form()
  defp make_canonical(spec, defaults \\ @default_children_spec_options)

  defp make_canonical({spec, options_keywords_list}, defaults) do
    spec = Bunch.listify(spec)
    {inner_specs, this_level_specs} = Enum.split_with(spec, &is_tuple(&1))

    {:ok, options} =
      Bunch.Config.parse(options_keywords_list, @children_spec_options_fields_specs)

    options =
      with %{crash_group: {group_name, :temporary}} <- options do
        options
        |> Map.delete(:crash_group)
        |> Map.merge(%{group: group_name, crash_group_mode: :temporary})
      end

    options = Map.merge(defaults, options)

    options_to_pass_to_nested =
      Enum.reject(options, fn {key, _value} -> key in [:clock_provider, :stream_sync] end)
      |> Map.new()

    defaults_for_nested = Map.merge(@default_children_spec_options, options_to_pass_to_nested)

    [{this_level_specs, options}] ++
      Enum.flat_map(inner_specs, &make_canonical(&1, defaults_for_nested))
  end

  defp make_canonical(specs, defaults) when is_list(specs) do
    Enum.flat_map(specs, &make_canonical(&1, defaults))
  end

  defp make_canonical(spec, defaults) do
    spec = Bunch.listify(spec)
    {:ok, options} = Bunch.Config.parse([], @children_spec_options_fields_specs)
    options = Map.merge(defaults, options)
    [{spec, options}]
  end

  defp setup_children(
         {children_definitions_with_given_options, options},
         spec_ref,
         state
       ) do
    children = ChildEntryParser.parse(children_definitions_with_given_options)
    children = Enum.map(children, &%{&1 | spec_ref: spec_ref})
    :ok = StartupUtils.check_if_children_names_unique(children, state)
    syncs = StartupUtils.setup_syncs(children, options.stream_sync)

    log_metadata =
      case state do
        %Bin.State{children_log_metadata: metadata} ->
          metadata ++ options.log_metadata

        %Pipeline.State{} ->
          options.log_metadata
      end

    children =
      StartupUtils.start_children(
        children,
        options.node,
        state.synchronization.clock_proxy,
        syncs,
        log_metadata,
        state.subprocess_supervisor,
        options.group
      )

    :ok = StartupUtils.maybe_activate_syncs(syncs, state)
    state = ClockHandler.choose_clock(children, options.clock_provider, state)
    state = %{state | children: Map.merge(state.children, Map.new(children, &{&1.name, &1}))}

    children_names = children |> Enum.map(& &1.name)
    children_pids = children |> Enum.map(& &1.pid)

    # adding crash group to state
    state =
      if options.crash_group_mode != nil do
        CrashGroupUtils.add_crash_group(
          {options.group, options.crash_group_mode},
          children_names,
          children_pids,
          state
        )
      else
        state
      end

    {children_names, state}
  end

  defp remove_unecessary_children_specs(children_definitions_list, state) do
    %{children: state_children} = state

    Enum.map(children_definitions_list, fn {children_definitions, children_spec_options} ->
      {children_definitions
       |> Enum.reject(fn
         {name, _child_spec, options} ->
           options.get_if_exists and Map.has_key?(state_children, name)
       end), children_spec_options}
    end)
  end

  @spec proceed_spec_startup(spec_ref(), Parent.state()) :: Parent.state()
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
      "Proceeding spec #{inspect(spec_ref)} startup: initializing, dependent specs: #{inspect(MapSet.to_list(spec_data.dependent_specs))}"
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
    {awaiting_responses, state} =
      Enum.flat_map_reduce(spec_data.links_ids, state, fn link_id, state ->
        %Membrane.Core.Parent.Link{from: from, to: to, spec_ref: spec_ref} =
          Map.fetch!(state.links, link_id)

        {output_awaiting, state} =
          LinkUtils.request_link(:output, from, to, spec_ref, link_id, state)

        {input_awaiting, state} =
          LinkUtils.request_link(:input, to, from, spec_ref, link_id, state)

        {output_awaiting ++ input_awaiting, state}
      end)

    spec_data = %{
      spec_data
      | awaiting_responses: MapSet.new(awaiting_responses),
        status: :linking_internally
    }

    Membrane.Logger.debug("Spec #{inspect(spec_ref)} status changed to linking internally")
    do_proceed_spec_startup(spec_ref, spec_data, state)
  end

  defp do_proceed_spec_startup(spec_ref, %{status: :linking_internally} = spec_data, state) do
    if Enum.empty?(spec_data.awaiting_responses) do
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
    state = remove_spec_from_dependencies(spec_ref, state)
    do_proceed_spec_startup(spec_ref, %{spec_data | status: :ready}, state)
  end

  defp do_proceed_spec_startup(
         spec_ref,
         %{status: :linked_internally} = spec_data,
         %Bin.State{} = state
       ) do
    state = Bin.PadController.respond_links(spec_ref, state)
    state = remove_spec_from_dependencies(spec_ref, state)
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

  @spec handle_link_response(Parent.Link.id(), Membrane.Pad.direction(), Parent.state()) ::
          Parent.state()
  def handle_link_response(link_id, direction, state) do
    with {:ok, %Link{spec_ref: spec_ref}} <- Map.fetch(state.links, link_id),
         true <- Map.has_key?(state.pending_specs, spec_ref) do
      state =
        update_in(
          state,
          [:pending_specs, spec_ref, :awaiting_responses],
          &MapSet.delete(&1, {link_id, direction})
        )

      proceed_spec_startup(spec_ref, state)
    else
      _other -> state
    end
  end

  @spec handle_child_initialized(Child.name(), Parent.state()) :: Parent.state()
  def handle_child_initialized(child, state) do
    %{spec_ref: spec_ref} = Parent.ChildrenModel.get_child_data!(state, child)
    state = put_in(state, [:children, child, :initialized?], true)
    proceed_spec_startup(spec_ref, state)
  end

  @spec handle_notify_child(
          {Child.name(), Membrane.ParentNotification.t()},
          Parent.state()
        ) :: :ok
  def handle_notify_child({child_name, message}, state) do
    %{pid: pid} = Parent.ChildrenModel.get_child_data!(state, child_name)
    Membrane.Core.Message.send(pid, :parent_notification, [message])
    :ok
  end

  @spec handle_remove_children(
          Child.name() | [Child.name()] | Child.group() | [Child.group()],
          Parent.state()
        ) :: Parent.state()
  def handle_remove_children(children_or_children_groups, state) do
    children_or_children_groups = Bunch.listify(children_or_children_groups)

    :ok = ensure_removed_children_exist!(children_or_children_groups, state)

    refs =
      state.children
      |> Enum.filter(fn {child_name, child_entry} ->
        child_name in children_or_children_groups or
          child_entry.group in children_or_children_groups
      end)
      |> Enum.map(fn {ref, _child_entry} -> ref end)

    Membrane.Logger.debug("Removing children: #{inspect(refs)}")

    state =
      if state.synchronization.clock_provider.provider in refs do
        ClockHandler.reset_clock(state)
      else
        state
      end

    data = Enum.map(refs, &Parent.ChildrenModel.get_child_data!(state, &1))
    {already_removing, data} = Enum.split_with(data, & &1.terminating?)

    if already_removing != [] do
      Membrane.Logger.warn("""
      Trying to remove children that are already being removed: #{Enum.map_join(already_removing, ", ", &inspect(&1.name))}. This may lead to 'unknown child' errors.
      """)
    end

    Enum.each(data, &Message.send(&1.pid, :terminate))

    children_names = Enum.map(data, & &1.name)
    state = remove_children_from_specs(children_names, state)

    Parent.ChildrenModel.update_children!(state, refs, &%{&1 | terminating?: true})
  end

  defp ensure_removed_children_exist!(removed_children_or_groups, state) do
    children_groups =
      MapSet.new(state.children, fn {_ref, data} -> data.group end)
      |> MapSet.delete(nil)

    removed_children_or_groups
    |> Enum.reject(fn name ->
      Map.has_key?(state.children, name) or MapSet.member?(children_groups, name)
    end)
    |> case do
      [] ->
        :ok

      children_names ->
        raise Membrane.ParentError, """
        Trying to remove children #{Enum.map_join(children_names, ", ", &inspect/1)}, while such children or children groups do not exist.
        Existing children are: #{Map.keys(state.children) |> inspect(pretty: true)}
        Existing children groups are: #{MapSet.to_list(children_groups) |> inspect(pretty: true)}
        """
    end
  end

  @spec handle_remove_link(Child.name(), Pad.ref(), Parent.state()) ::
          Parent.state()
  def handle_remove_link(child_name, pad_ref, state) do
    LinkUtils.remove_link(child_name, pad_ref, state)
  end

  defp remove_children_from_specs(removed_children, state) do
    removed_children = Bunch.listify(removed_children) |> MapSet.new()

    removed_children_specs =
      removed_children
      |> Enum.map(&get_in(state, [:children, &1, :spec_ref]))

    removed_links_ids =
      state.links
      |> Map.values()
      |> Enum.filter(
        &(MapSet.member?(removed_children, &1.from.child) or
            MapSet.member?(removed_children, &1.to.child))
      )
      |> MapSet.new(& &1.id)

    removed_links_specs =
      removed_links_ids
      |> Enum.map(&get_in(state, [:links, &1, :spec_ref]))

    updated_specs =
      Enum.uniq(removed_children_specs ++ removed_links_specs)
      |> Enum.filter(&Map.has_key?(state.pending_specs, &1))
      |> Map.new(fn spec_ref ->
        spec_data =
          Map.get(state.pending_specs, spec_ref)
          |> remove_children_and_links_from_spec_data(
            removed_children,
            removed_links_ids
          )

        {spec_ref, spec_data}
      end)

    state = Map.update!(state, :pending_specs, &Map.merge(&1, updated_specs))

    updated_specs
    |> Map.keys()
    |> Enum.reduce(state, &proceed_spec_startup/2)
  end

  @spec remove_link_from_specs(Link.id(), Parent.state()) :: Parent.state()
  def remove_link_from_specs(link_id, state) when is_reference(link_id) do
    link = Map.fetch!(state.links, link_id)
    spec_ref = link.spec_ref

    if Map.has_key?(state.pending_specs, spec_ref) do
      state =
        update_in(
          state,
          [:pending_specs, spec_ref],
          &remove_children_and_links_from_spec_data(&1, [], [link_id])
        )

      proceed_spec_startup(spec_ref, state)
    else
      state
    end
  end

  defp remove_children_and_links_from_spec_data(spec_data, removed_children, removed_links_ids) do
    removed_children = MapSet.new(removed_children)
    removed_links_ids = MapSet.new(removed_links_ids)

    children_names =
      spec_data.children_names
      |> MapSet.difference(removed_children)

    links_ids =
      spec_data.links_ids
      |> Enum.reject(&MapSet.member?(removed_links_ids, &1))

    awaiting_responses =
      spec_data.awaiting_responses
      |> Enum.reject(fn {link_id, _direction} ->
        MapSet.member?(removed_links_ids, link_id)
      end)
      |> MapSet.new()

    %{
      spec_data
      | children_names: children_names,
        links_ids: links_ids,
        awaiting_responses: awaiting_responses
    }
  end

  @spec handle_child_pad_removed(Child.name(), Pad.ref(), Parent.state()) :: Parent.state()
  def handle_child_pad_removed(child, pad, state) do
    Membrane.Logger.debug_verbose("Child #{inspect(child)} removed pad #{inspect(pad)}")

    child_terminating? = Parent.ChildrenModel.get_child_data!(state, child).terminating?

    if child_terminating? do
      state
    else
      state =
        CallbackHandler.exec_and_handle_callback(
          :handle_child_pad_removed,
          Component.action_handler(state),
          %{context: &Component.context_from_state/1},
          [child, pad],
          state
        )

      LinkUtils.handle_child_pad_removed(child, pad, state)
    end
  end

  @doc """
  Handles death of a child:
  - removes it from state
  - unlinks it from other children
  - handles crash group (if applicable)
  """
  @spec handle_child_death(
          child_name :: Child.name(),
          reason :: any(),
          state :: Parent.state()
        ) :: {:stop | :continue, Parent.state()}
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
      state =
        group.members
        |> Enum.filter(&Map.has_key?(state.children, &1))
        |> remove_children_from_specs(state)

      {result, state} =
        crash_all_group_members(group, child_name, state)
        |> remove_child_from_crash_group(group, child_pid)

      if result == :removed do
        exec_handle_crash_group_down_callback(
          group.name,
          group.members,
          group.crash_initiator || child_name,
          state
        )
      else
        state
      end
      |> Bunch.Access.delete_in([:children, child_name])
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
    {spec_ref, state} = pop_in(state, [:pending_specs, spec_ref])

    case spec_ref do
      nil ->
        state

      %{status: status} when status in @spec_dependency_requiring_statuses ->
        Membrane.Logger.debug("Cleaning spec #{inspect(spec_ref)}")
        remove_spec_from_dependencies(spec_ref, state)

      _spec_data ->
        Membrane.Logger.debug("Cleaning spec #{inspect(spec_ref)}")
        state
    end
  end

  defp remove_spec_from_dependencies(spec_ref, state) do
    related_specs =
      state.pending_specs
      |> Enum.filter(fn {_ref, data} -> MapSet.member?(data.dependent_specs, spec_ref) end)
      |> Map.new(fn {ref, data} ->
        {ref, Map.update!(data, :dependent_specs, &MapSet.delete(&1, spec_ref))}
      end)

    state = %{state | pending_specs: Map.merge(state.pending_specs, related_specs)}
    related_specs |> Map.keys() |> Enum.reduce(state, &proceed_spec_startup/2)
  end

  defp exec_handle_crash_group_down_callback(
         group_name,
         group_members,
         crash_initiator,
         state
       ) do
    context_generator =
      &Component.context_from_state(&1,
        members: group_members,
        crash_initiator: crash_initiator
      )

    CallbackHandler.exec_and_handle_callback(
      :handle_crash_group_down,
      Membrane.Core.Pipeline.ActionHandler,
      %{context: context_generator},
      [group_name],
      state
    )
  end

  # called when process was a member of a crash group
  @spec crash_all_group_members(CrashGroup.t(), Child.name(), Parent.state()) ::
          Parent.state()
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
