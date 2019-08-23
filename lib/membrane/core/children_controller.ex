defmodule Membrane.Core.Parent.ChildrenController do
  @moduledoc false
  use Bunch
  use Membrane.Log, tags: :core

  alias Membrane.{Bin, CallbackError, Child, Element, Spec, ParentError}
  alias Membrane.Core.{CallbackHandler, Message, Parent}
  alias Membrane.Core.Link
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
  def handle_spec(spec_controller_module, %{children: children_spec, links: links}, state) do
    debug("""
    Initializing spec
    children: #{inspect(children_spec)}
    links: #{inspect(links)}
    """)

    parsed_children = children_spec |> parse_children()

    {:ok, state} = {parsed_children |> check_if_children_names_unique(state), state}

    children = parsed_children |> start_children()
    {:ok, state} = children |> add_children(state)

    {{:ok, links}, state} = {links |> parse_links(), state}
    {links, state} = links |> spec_controller_module.resolve_links(state)
    {:ok, state} = links |> spec_controller_module.link_children(state)
    {children_names, children_pids} = children |> Enum.unzip()
    {:ok, state} = {children_pids |> set_children_watcher(), state}
    {:ok, state} = exec_handle_spec_started(spec_controller_module, children_names, state)

    children_pids
    |> Enum.each(&change_playback_state(&1, state.playback.state))

    {{:ok, children_names}, state}
  end

  @spec change_playback_state(pid, Membrane.PlaybackState.t()) :: :ok
  defp change_playback_state(pid, new_state)
       when Membrane.PlaybackState.is_playback_state(new_state) do
    alias Membrane.Core.Message
    require Message
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

  @spec start_children([parsed_child_t]) :: [Parent.ChildrenModel.child_t()]
  def start_children(children) do
    debug("Starting children: #{inspect(children)}")

    children |> Enum.map(&start_child/1)
  end

  @spec add_children([parsed_child_t()], Parent.ChildrenModel.t()) ::
          Type.stateful_try_t(Parent.ChildrenModel.t())
  def add_children(children, state) do
    children
    |> Bunch.Enum.try_reduce(state, fn {name, pid}, state ->
      state |> Parent.ChildrenModel.add_child(name, pid)
    end)
  end

  defp start_child(%{module: module} = spec) do
    case child_type(module) do
      :bin ->
        start_child_bin(spec)

      :element ->
        start_child_element(spec)
    end
  end

  defp child_type(module) do
    if module |> Bunch.Module.check_behaviour(:membrane_bin?) do
      :bin
    else
      :element
    end
  end

  defp start_child_element(%{name: name, module: module, options: options}) do
    debug("Pipeline: starting child: name: #{inspect(name)}, module: #{inspect(module)}")

    with {:ok, pid} <- Element.start_link(self(), module, name, options),
         :ok <- Element.set_controlling_pid(pid, self()) do
      {name, pid}
    else
      {:error, reason} ->
        raise ParentError,
              "Cannot start child #{inspect(name)}, \
              reason: #{inspect(reason, pretty: true)}"
    end
  end

  defp start_child_bin(%{name: name, module: module, options: options}) do
    with {:ok, pid} <- Bin.start_link(name, module, options, []),
         :ok <- Bin.set_controlling_pid(pid, self()) do
      {name, pid}
    else
      {:error, reason} ->
        raise ParentError,
              "Cannot start child #{inspect(name)}, \
              reason: #{inspect(reason, pretty: true)}"
    end
  end

  @spec set_children_watcher([pid]) :: :ok
  def set_children_watcher(elements_pids) do
    elements_pids
    |> Enum.each(fn pid ->
      :ok = set_watcher(pid, self())
    end)
  end

  defp set_watcher(server, watcher, timeout \\ 5000) when is_pid(server) do
    Message.call(server, :set_watcher, watcher, [], timeout)
  end

  defp exec_handle_spec_started(spec_controller_module, children_names, state) do
    callback_res =
      CallbackHandler.exec_and_handle_callback(
        :handle_spec_started,
        spec_controller_module.action_handler_module,
        [children_names],
        state
      )

    with {:ok, _} <- callback_res do
      callback_res
    else
      {{:error, reason}, _state} ->
        raise CallbackError, """
        Callback :handle_spec_started failed with reason: #{inspect(reason)}
        """
    end
  end
end
