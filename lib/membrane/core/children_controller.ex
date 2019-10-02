defmodule Membrane.Core.Parent.ChildrenController do
  @moduledoc false
  use Bunch
  use Membrane.Log, tags: :core

  alias Membrane.{Bin, CallbackError, Child, Element, ParentError, Spec, Sync}
  alias Membrane.Core
  alias Core.{CallbackHandler, Message, Parent}
  alias Core.Link
  alias Bunch.Type

  require Bin
  require Element
  require Message
  require Membrane.PlaybackState

  @typep parsed_child_t :: %{name: Child.name_t(), module: module, options: Keyword.t()}

  @callback resolve_links([Link.t()], Parent.ChildrenModel.t()) :: [Link.resolved_t()]

  @callback link_children([Link.resolved_t()], Parent.ChildrenModel.t()) :: Type.try_t()

  @callback action_handler_module :: module()

  @spec handle_spec(module(), Spec.t(), Parent.ChildrenModel.t()) ::
          Type.stateful_try_t([Child.name_t()], Parent.ChildrenModel.t())
  def handle_spec(spec_controller_module, spec, state) do
    %Spec{
      children: children_spec,
      links: links,
      stream_sync: stream_sync,
      clock_provider: clock_provider
    } = spec

    debug("""
    Initializing spec
    children: #{inspect(children_spec)}
    links: #{inspect(links)}
    """)

    parsed_children = children_spec |> parse_children()

    {:ok, state} = {parsed_children |> check_if_children_names_unique(state), state}

    syncs = setup_syncs(parsed_children, stream_sync)

    children = parsed_children |> start_children(state.clock_proxy, syncs)

    if state.playback.state == :playing do
      syncs |> MapSet.new(&elem(&1, 1)) |> Bunch.Enum.try_each(&Sync.activate/1)
    end

    {:ok, state} = children |> add_children(state)

    {:ok, state} = Parent.Action.choose_clock(children, clock_provider, state) # TODO where choose_cloc/3 should be?

    {{:ok, links}, state} = {links |> parse_links(), state}
    {links, state} = links |> spec_controller_module.resolve_links(state)
    {:ok, state} = links |> spec_controller_module.link_children(state)
    {children_names, children_data} = children |> Enum.unzip()
    {:ok, state} = exec_handle_spec_started(spec_controller_module, children_names, state)

    children_data
    |> Enum.each(&change_playback_state(&1.pid, state.playback.state))

    {{:ok, children_names}, state}
  end

  defp setup_syncs(children, :sinks) do
    sinks =
      children |> Enum.filter(&(&1.module.membrane_element_type == :sink)) |> Enum.map(& &1.name)

    setup_syncs(children, [sinks])
  end

  defp setup_syncs(children, stream_sync) do
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

  @spec change_playback_state(pid, Membrane.PlaybackState.t()) :: :ok
  defp change_playback_state(pid, new_state)
       when Membrane.PlaybackState.is_playback_state(new_state) do
    Message.send(pid, :change_playback_state, new_state)
    :ok
  end

  defp parse_links(links), do: links |> Bunch.Enum.try_map(&Link.parse/1)

  defguardp is_child_name(term)
            when is_atom(term) or
                   (is_tuple(term) and tuple_size(term) == 2 and is_atom(elem(term, 0)) and
                      is_integer(elem(term, 1)) and elem(term, 1) >= 0)

  @spec parse_children(Spec.children_spec_t() | any) :: [parsed_child_t]
  def parse_children(children) when is_map(children) or is_list(children),
    do: children |> Enum.map(&parse_child/1)

  def parse_child({name, %module{} = options})
      when is_child_name(name) do
    %{name: name, module: module, options: options}
  end

  def parse_child({name, module})
      when is_child_name(name) and is_atom(module) do
    options = module |> Bunch.Module.struct()
    %{name: name, module: module, options: options}
  end

  def parse_child(config) do
    raise ParentError, "Invalid children config: #{inspect(config, pretty: true)}"
  end

  @spec check_if_children_names_unique([parsed_child_t], Parent.ChildrenModel.t()) ::
          Type.try_t()
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

  #@spec start_children([parsed_child_t], parent_clock :: Clock.t(), syncs :: m) :: [Parent.ChildrenModel.child_t()] # TODO
  def start_children(children, parent_clock, syncs) do
    debug("Starting children: #{inspect(children)}")

    children |> Enum.map(&start_child(&1, parent_clock, syncs))
  end

  @spec add_children([parsed_child_t()], Parent.ChildrenModel.t()) ::
          Type.stateful_try_t(Parent.ChildrenModel.t())
  def add_children(children, state) do
    children
    |> Bunch.Enum.try_reduce(state, fn {name, pid}, state ->
      state |> Parent.ChildrenModel.add_child(name, pid)
    end)
  end

  defp start_child(%{name: name, module: module} = spec, parent_clock, syncs) do
    sync = syncs |> Map.get(name, Sync.no_sync())
    case child_type(module) do
      :bin ->
        start_child_bin(spec, parent_clock, sync) # TODO set clock and syncs for bin as well

      :element ->
        start_child_element(spec, parent_clock, sync)
    end
  end

  defp child_type(module) do
    if module |> Bunch.Module.check_behaviour(:membrane_bin?) do
      :bin
    else
      :element
    end
  end

  defp start_child_element(%{name: name, module: module, options: options}, parent_clock, sync) do
    debug("Pipeline: starting child: name: #{inspect(name)}, module: #{inspect(module)}")

    with {:ok, pid} <- Core.Element.start_link(%{parent: self(), module: module, name: name, user_options: options, clock: parent_clock, sync: sync}),
         :ok <- Message.call(pid, :set_controlling_pid, self()),
         {:ok, %{clock: clock}} <- Message.call(pid, :handle_watcher, self()) do
      {name, %{pid: pid, clock: clock, sync: sync}}
    else
      {:error, reason} ->
        raise ParentError,
              "Cannot start child #{inspect(name)}, \
              reason: #{inspect(reason, pretty: true)}"
    end
  end

  defp start_child_bin(%{name: name, module: module, options: options}, parent_clock, sync) do
    # TODO redo start link of Bin to accept parent clock and options as map
    with {:ok, pid} <- Bin.start_link(name, module, options, []),
         :ok <- Bin.set_controlling_pid(pid, self()),
         {:ok, %{clock: clock}} <- Message.call(pid, :handle_watcher, self()) do
      {name, %{pid: pid, clock: clock, sync: sync}}
    else
      {:error, reason} ->
        raise ParentError,
              "Cannot start child #{inspect(name)}, \
              reason: #{inspect(reason, pretty: true)}"
    end
  end

  defp exec_handle_spec_started(spec_controller_module, children_names, state) do
    callback_res =
      CallbackHandler.exec_and_handle_callback(
        :handle_spec_started,
        spec_controller_module.action_handler_module,
        [children_names],
        state
      )

    case callback_res do
      {:ok, _} ->
        callback_res

      {{:error, reason}, _state} ->
        raise CallbackError, """
        Callback :handle_spec_started failed with reason: #{inspect(reason)}
        """
    end
  end
end
