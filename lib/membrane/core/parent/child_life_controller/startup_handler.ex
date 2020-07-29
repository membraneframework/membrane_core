defmodule Membrane.Core.Parent.ChildLifeController.StartupHandler do
  @moduledoc false
  use Bunch

  require Membrane.Logger
  require Membrane.Core.Message
  require Membrane.Core.Parent

  alias Membrane.{CallbackError, Clock, ParentError, Sync}
  alias Membrane.Core.{Bin, CallbackHandler, Element, Message, Parent, Pipeline}
  alias Membrane.Core.Parent.{ChildEntry, State}

  @spec check_if_children_names_unique([ChildEntry.t()], State.t()) ::
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

  @spec setup_syncs([ChildEntry.t()], :sinks | [[Membrane.Child.name_t()]]) :: %{
          Membrane.Child.name_t() => Sync.t()
        }
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
          [ChildEntry.t()],
          parent_clock :: Clock.t(),
          syncs :: %{Membrane.Child.name_t() => pid()},
          log_metadata :: Keyword.t()
        ) :: [ChildEntry.resolved_t()]
  def start_children(children, parent_clock, syncs, log_metadata) do
    Membrane.Logger.debug("Starting children: #{inspect(children)}")

    children |> Enum.map(&start_child(&1, parent_clock, syncs, log_metadata))
  end

  @spec add_children([ChildEntry.resolved_t()], State.t()) ::
          {:ok | {:error, any}, State.t()}
  def add_children(children, state) do
    children
    |> Bunch.Enum.try_reduce(state, fn child, state ->
      state |> Parent.ChildrenModel.add_child(child.name, child)
    end)
  end

  @spec maybe_activate_syncs(%{Membrane.Child.name_t() => Sync.t()}, State.t()) ::
          :ok | {:error, :bad_activity_request}
  def maybe_activate_syncs(syncs, %{playback: %{state: :playing}}) do
    syncs |> MapSet.new(&elem(&1, 1)) |> Bunch.Enum.try_each(&Sync.activate/1)
  end

  def maybe_activate_syncs(_syncs, _state) do
    :ok
  end

  @spec exec_handle_spec_started([Membrane.Child.name_t()], State.t()) ::
          {:ok, State.t()} | no_return
  def exec_handle_spec_started(children_names, state) do
    context = Parent.callback_context_generator(SpecStarted, state)

    action_handler =
      case state do
        %Pipeline.State{} -> Pipeline.ActionHandler
        %Bin.State{} -> Bin.ActionHandler
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

  defp start_child(child, parent_clock, syncs, log_metadata) do
    %ChildEntry{name: name, module: module, options: options} = child
    Membrane.Logger.debug("Starting child: name: #{inspect(name)}, module: #{inspect(module)}")
    sync = syncs |> Map.get(name, Sync.no_sync())

    log_metadata =
      log_metadata |> Keyword.put(:parent_path, Membrane.Helper.PathLocator.get_path())

    start_result =
      cond do
        Bunch.Module.check_behaviour(module, :membrane_element?) ->
          Element.start_link(%{
            parent: self(),
            module: module,
            name: name,
            user_options: options,
            clock: parent_clock,
            sync: sync,
            log_metadata: log_metadata
          })

        Bunch.Module.check_behaviour(module, :membrane_bin?) ->
          unless sync == Sync.no_sync() do
            raise ParentError,
                  "Cannot start child #{inspect(name)}, \
                  reason: bin cannot be synced with other elements"
          end

          Membrane.Bin.start_link(name, module, options, log_metadata, [])

        true ->
          raise ParentError, """
          Module #{inspect(module)} is neither Membrane Element nor Bin.
          Make sure that given module is the right one, implements proper behaviour
          and all needed dependencies are properly specified in the Mixfile.
          """
      end

    with {:ok, pid} <- start_result,
         :ok <- Message.call(pid, :set_controlling_pid, self()),
         {:ok, %{clock: clock}} <- Message.call(pid, :handle_watcher, self()) do
      %ChildEntry{child | pid: pid, clock: clock, sync: sync}
    else
      {:error, reason} ->
        raise ParentError,
              "Cannot start child #{inspect(name)}, \
              reason: #{inspect(reason, pretty: true)}"
    end
  end
end
