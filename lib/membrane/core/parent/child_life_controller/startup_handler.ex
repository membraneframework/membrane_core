defmodule Membrane.Core.Parent.ChildLifeController.StartupHandler do
  @moduledoc false
  use Bunch

  alias Membrane.{CallbackError, ChildEntry, Clock, Core, ParentError, Sync}
  alias Membrane.Core.{CallbackHandler, Component, Message, Parent}
  alias Membrane.Core.Parent.{ChildEntryParser, ChildrenModel}

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
          log_metadata :: Keyword.t()
        ) :: [ChildEntry.t()]
  def start_children(children, node, parent_clock, syncs, log_metadata) do
    # If the node is set to the current node, set it to nil, to avoid race conditions when
    # distribution changes
    node = if node == node(), do: nil, else: node

    Membrane.Logger.debug(
      "Starting children: #{inspect(children)}#{if node, do: " on node #{node}"}"
    )

    children |> Enum.map(&start_child(&1, node, parent_clock, syncs, log_metadata))
  end

  @spec add_children([ChildEntry.t()], Parent.state_t()) ::
          {:ok | {:error, any}, Parent.state_t()}
  def add_children(children, state) do
    children
    |> Bunch.Enum.try_reduce(state, fn child, state ->
      state |> ChildrenModel.add_child(child.name, child)
    end)
  end

  @spec maybe_activate_syncs(%{Membrane.Child.name_t() => Sync.t()}, Parent.state_t()) ::
          :ok | {:error, :bad_activity_request}
  def maybe_activate_syncs(syncs, %{playback: %{state: :playing}}) do
    syncs |> MapSet.new(&elem(&1, 1)) |> Bunch.Enum.try_each(&Sync.activate/1)
  end

  def maybe_activate_syncs(_syncs, _state) do
    :ok
  end

  @spec exec_handle_spec_started([Membrane.Child.name_t()], Parent.state_t()) ::
          {:ok, Parent.state_t()} | no_return
  def exec_handle_spec_started(children_names, state) do
    context = Component.callback_context_generator(:parent, SpecStarted, state)

    action_handler =
      case state do
        %Core.Pipeline.State{} -> Core.Pipeline.ActionHandler
        %Core.Bin.State{} -> Core.Bin.ActionHandler
      end

    callback_res =
      CallbackHandler.exec_and_handle_callback(
        :handle_spec_started,
        action_handler,
        %{context: context},
        [children_names],
        state
      )

    case callback_res do
      {:ok, _} ->
        callback_res

      {{:error, reason}, _state} ->
        raise CallbackError,
          message: """
          Callback :handle_spec_started failed with reason: #{inspect(reason)}
          """
    end
  end

  @spec init_playback_state([Membrane.Child.name_t()], Parent.state_t()) :: Parent.state_t()
  def init_playback_state(children_names, state) do
    case state.playback.pending_state || state.playback.state do
      :stopped ->
        state

      expected_playback ->
        {:ok, state} =
          ChildrenModel.update_children(state, children_names, fn child ->
            Message.send(child.pid, :change_playback_state, expected_playback)
            %{child | playback_synced?: false}
          end)

        state
    end
  end

  defp start_child(child, node, parent_clock, syncs, log_metadata) do
    %ChildEntry{name: name, module: module, options: options} = child
    Membrane.Logger.debug("Starting child: name: #{inspect(name)}, module: #{inspect(module)}")
    sync = syncs |> Map.get(name, Sync.no_sync())

    log_metadata = log_metadata |> Keyword.put(:parent_path, Membrane.ComponentPath.get())

    start_result =
      case child.component_type do
        :element ->
          Core.Element.start(%{
            parent: self(),
            module: module,
            name: name,
            node: node,
            user_options: options,
            parent_clock: parent_clock,
            sync: sync,
            log_metadata: log_metadata
          })

        :bin ->
          unless sync == Sync.no_sync() do
            raise ParentError,
                  "Cannot start child #{inspect(name)}, \
                  reason: bin cannot be synced with other elements"
          end

          Core.Bin.start(%{
            parent: self(),
            name: name,
            module: module,
            node: node,
            user_options: options,
            parent_clock: parent_clock,
            log_metadata: log_metadata
          })
      end

    with {:ok, pid} <- start_result,
         {:ok, clock} <- Message.call(pid, :get_clock) do
      %ChildEntry{child | pid: pid, clock: clock, sync: sync}
    else
      {:error, reason} ->
        raise ParentError,
              "Cannot start child #{inspect(name)}, \
              reason: #{inspect(reason, pretty: true)}"
    end
  end
end
