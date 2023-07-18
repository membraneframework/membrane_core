defmodule Membrane.Core.Parent.ChildLifeController.StartupUtils do
  @moduledoc false
  use Bunch

  alias Membrane.{ChildEntry, Core, ParentError, Sync}
  alias Membrane.Core.{CallbackHandler, Component, Message, Parent, SubprocessSupervisor}
  alias Membrane.Core.Parent.{ChildEntryParser, ChildLifeController}

  require Membrane.Core.Component
  require Membrane.Core.Message
  require Membrane.Logger

  @spec check_if_children_names_unique([ChildEntryParser.raw_child_entry()], Parent.state()) ::
          :ok | no_return
  def check_if_children_names_unique(children, state) do
    %{children: state_children} = state

    children
    |> Enum.map(& &1.name)
    |> Kernel.++(Map.keys(state_children))
    |> Bunch.Enum.duplicates()
    |> case do
      [] ->
        :ok

      duplicates ->
        raise ParentError, "Duplicated names in children specification: #{inspect(duplicates)}"
    end
  end

  @spec setup_syncs([ChildEntryParser.raw_child_entry()], :sinks | [[Membrane.Child.name()]]) ::
          %{Membrane.Child.name() => Sync.t()}
  def setup_syncs(children, :sinks) do
    sinks =
      children
      |> Enum.filter(
        &(Membrane.Element.element?(&1.module) and &1.module.membrane_element_type == :sink)
      )
      |> Enum.map(& &1.name)

    setup_syncs(children, [sinks])
  end

  def setup_syncs(children, stream_sync) do
    children_names = children |> MapSet.new(& &1.name)
    all_to_sync = stream_sync |> List.flatten()

    withl dups: [] <- all_to_sync |> Bunch.Enum.duplicates(),
          unknown: [] <- all_to_sync |> Enum.reject(&(&1 in children_names)) do
      stream_sync
      |> Enum.flat_map(fn elements ->
        {:ok, sync} = Sync.start_link(empty_exit?: true)
        elements |> Enum.map(&{&1, sync})
      end)
      |> Map.new()
    else
      dups: dups ->
        raise ParentError,
              "Cannot apply sync - duplicate elements: #{dups |> Enum.join(", ")}"

      unknown: unknown ->
        raise ParentError,
              "Cannot apply sync - unknown elements: #{unknown |> Enum.join(", ")}"
    end
  end

  @spec start_children(
          [ChildEntryParser.raw_child_entry()],
          node() | nil,
          syncs :: %{Membrane.Child.name() => pid()},
          log_metadata :: Keyword.t(),
          group :: Membrane.Child.group(),
          Parent.state()
        ) :: [ChildEntry.t()]
  def start_children(
        children,
        node,
        syncs,
        log_metadata,
        group,
        state
      ) do
    # If the node is set to the current node, set it to nil, to avoid race conditions when
    # distribution changes
    node = if node == node(), do: nil, else: node

    Membrane.Logger.debug(
      "Starting children: #{inspect(children)} in children group: #{inspect(group)}#{if node, do: " on node #{node}"}"
    )

    children
    |> Enum.map(&start_child(&1, node, syncs, log_metadata, group, state))
  end

  @spec maybe_activate_syncs(%{Membrane.Child.name() => Sync.t()}, Parent.state()) ::
          :ok | {:error, :bad_activity_request}
  def maybe_activate_syncs(syncs, %{playback: :playing}) do
    syncs |> MapSet.new(&elem(&1, 1)) |> Bunch.Enum.try_each(&Sync.activate/1)
  end

  def maybe_activate_syncs(_syncs, _state) do
    :ok
  end

  @spec exec_handle_spec_started([Membrane.Child.name()], Parent.state()) :: Parent.state()
  def exec_handle_spec_started(children_names, state) do
    action_handler = Component.action_handler(state)

    CallbackHandler.exec_and_handle_callback(
      :handle_spec_started,
      action_handler,
      %{context: &Component.context_from_state/1},
      [children_names],
      state
    )
  end

  @spec check_if_children_names_and_children_groups_ids_are_unique(
          ChildLifeController.children_spec_canonical_form(),
          Parent.state()
        ) :: :ok
  def check_if_children_names_and_children_groups_ids_are_unique(children_definitions, state) do
    state_children_groups =
      Enum.map(state.children, fn {_child_name, child_entry} -> child_entry.group end)

    new_children_groups =
      Enum.map(children_definitions, fn {_children, options} -> options.group end)

    state_children_names = Map.keys(state.children)

    new_children_names =
      children_definitions
      |> Enum.flat_map(fn {children, _options} -> children end)
      |> Enum.map(fn {child_name, _child_module, _options} -> child_name end)

    duplicated = Enum.filter(new_children_groups, &(&1 in state_children_names))

    if duplicated != [],
      do:
        raise(
          Membrane.ParentError,
          "Cannot create children groups with ids: #{inspect(duplicated)} since
    there are already children with such names."
        )

    duplicated = Enum.filter(new_children_names, &(&1 in state_children_groups))

    if duplicated != [],
      do:
        raise(
          Membrane.ParentError,
          "Cannot spawn children with names: #{inspect(duplicated)} since
    there are already children groups with such ids."
        )

    duplicated = Enum.filter(new_children_names, &(&1 in new_children_groups))

    if duplicated != [],
      do:
        raise(
          Membrane.ParentError,
          "Cannot proceed, since the children group ids and children names created in this process are duplicating: #{inspect(duplicated)}"
        )

    :ok
  end

  defp start_child(child, node, syncs, log_metadata, group, state) do
    %ChildEntry{name: name, module: module, options: options} = child

    Membrane.Logger.debug(
      "Starting child: name: #{inspect(name)}, module: #{inspect(module)} in children group: #{inspect(group)}"
    )

    sync = syncs |> Map.get(name, Sync.no_sync())

    params = %{
      parent: self(),
      module: module,
      name: name,
      node: node,
      user_options: options,
      parent_clock: state.synchronization.clock_proxy,
      sync: sync,
      parent_path: Membrane.ComponentPath.get(),
      group: group,
      log_metadata: log_metadata,
      stalker: state.stalker
    }

    component_module =
      case child.component_type do
        :element ->
          Core.Element

        :bin ->
          unless sync == Sync.no_sync() do
            raise ParentError,
                  "Cannot start child #{inspect(name)}, \
                  reason: bin cannot be synced with other elements"
          end

          Core.Bin
      end

    with {:ok, child_pid} <-
           SubprocessSupervisor.start_component(
             state.subprocess_supervisor,
             name,
             component_module,
             params
           ),
         {:ok, clock} <- receive_clock(name) do
      %ChildEntry{
        child
        | pid: child_pid,
          clock: clock,
          sync: sync,
          group: group
      }
    else
      {:error, reason} ->
        # ignore clock if element couldn't be started
        _clock = receive_clock(name)
        raise ParentError, "Error starting child #{inspect(name)}, reason: #{inspect(reason)}"
    end
  end

  defp receive_clock(child_name) do
    receive do
      Message.new(:clock, [^child_name, clock]) -> {:ok, clock}
    after
      0 -> {:error, :did_not_receive_clock}
    end
  end
end
