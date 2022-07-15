defmodule Membrane.Core.Parent.ChildLifeController.StartupHandler do
  @moduledoc false
  use Bunch

  alias Membrane.{ChildEntry, Clock, Core, ParentError, Sync}
  alias Membrane.Core.{CallbackHandler, Component, Message, Parent}
  alias Membrane.Core.Parent.{ChildEntryParser, ChildrenSupervisor}

  require Membrane.Core.Component
  require Membrane.Core.Message
  require Membrane.Logger

  @spec check_if_children_names_unique([ChildEntryParser.raw_child_entry_t()], Parent.state_t()) ::
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

  @spec setup_syncs([ChildEntryParser.raw_child_entry_t()], :sinks | [[Membrane.Child.name_t()]]) ::
          %{Membrane.Child.name_t() => Sync.t()}
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
          [ChildEntryParser.raw_child_entry_t()],
          node() | nil,
          parent_clock :: Clock.t(),
          syncs :: %{Membrane.Child.name_t() => pid()},
          log_metadata :: Keyword.t(),
          supervisor :: pid
        ) :: [ChildEntry.t()]
  def start_children(children, node, parent_clock, syncs, log_metadata, supervisor) do
    # If the node is set to the current node, set it to nil, to avoid race conditions when
    # distribution changes
    node = if node == node(), do: nil, else: node

    Membrane.Logger.debug(
      "Starting children: #{inspect(children)}#{if node, do: " on node #{node}"}"
    )

    children |> Enum.map(&start_child(&1, node, parent_clock, syncs, log_metadata, supervisor))
  end

  @spec add_children([ChildEntry.t()], Parent.state_t()) :: Parent.state_t()
  def add_children(children, state) do
    children =
      Enum.reduce(children, state.children, fn child, children ->
        Map.put(children, child.name, child)
      end)

    %{state | children: children}
  end

  @spec maybe_activate_syncs(%{Membrane.Child.name_t() => Sync.t()}, Parent.state_t()) ::
          :ok | {:error, :bad_activity_request}
  def maybe_activate_syncs(syncs, %{playback: %{state: :playing}}) do
    syncs |> MapSet.new(&elem(&1, 1)) |> Bunch.Enum.try_each(&Sync.activate/1)
  end

  def maybe_activate_syncs(_syncs, _state) do
    :ok
  end

  @spec exec_handle_spec_started([Membrane.Child.name_t()], Parent.state_t()) :: Parent.state_t()
  def exec_handle_spec_started(children_names, state) do
    context = Component.callback_context_generator(:parent, SpecStarted, state)

    action_handler =
      case state do
        %Core.Pipeline.State{} -> Core.Pipeline.ActionHandler
        %Core.Bin.State{} -> Core.Bin.ActionHandler
      end

    CallbackHandler.exec_and_handle_callback(
      :handle_spec_started,
      action_handler,
      %{context: context},
      [children_names],
      state
    )
  end

  defp start_child(child, node, parent_clock, syncs, log_metadata, supervisor) do
    %ChildEntry{name: name, module: module, options: options} = child
    Membrane.Logger.debug("Starting child: name: #{inspect(name)}, module: #{inspect(module)}")
    sync = syncs |> Map.get(name, Sync.no_sync())
    component_path = Membrane.ComponentPath.get()

    params = %{
      parent: self(),
      module: module,
      name: name,
      node: node,
      user_options: options,
      parent_clock: parent_clock,
      sync: sync,
      setup_logger: fn _pid ->
        Logger.metadata(log_metadata)

        name_str =
          "#{if String.valid?(name), do: name, else: inspect(name)}#{if child.component_type == :bin, do: "/", else: ""}"

        Membrane.ComponentPath.set_and_append(component_path, name_str)
        Membrane.Logger.set_prefix(Membrane.ComponentPath.get_formatted())
        log_metadata
      end
    }

    start_fun =
      case child.component_type do
        :element ->
          fn -> Core.Element.start_link(params) end

        :bin ->
          unless sync == Sync.no_sync() do
            raise ParentError,
                  "Cannot start child #{inspect(name)}, \
                  reason: bin cannot be synced with other elements"
          end

          fn -> Core.Bin.start_link(params) end
      end

    with {:ok, child_pid} <- ChildrenSupervisor.start_child(supervisor, name, start_fun) do
      clock = Message.call!(child_pid, :get_clock)
      %ChildEntry{child | pid: child_pid, clock: clock, sync: sync}
    else
      {:error, reason} ->
        raise ParentError, "Error starting child #{inspect(name)}, reason: #{inspect(reason)}"
    end
  end
end
