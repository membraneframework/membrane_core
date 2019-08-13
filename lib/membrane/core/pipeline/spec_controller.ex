defmodule Membrane.Core.Pipeline.SpecController do
  use Bunch
  use Membrane.Log, tags: :core
  use Membrane.Core.PlaybackRequestor

  alias Membrane.{Spec, PipelineError}
  # TODO Link should be moved out of Pipeline
  alias Membrane.Core.Pipeline.Link

  alias Membrane.Core.{
    ChildrenController,
    ParentState,
    Message,
    CallbackHandler
  }

  alias Membrane.Element

  require Message

  @spec handle_spec(Spec.t(), State.t()) :: Type.stateful_try_t([Element.name_t()], State.t())
  def handle_spec(%Spec{children: children_spec, links: links}, state) do
    debug("""
    Initializing pipeline spec
    children: #{inspect(children_spec)}
    links: #{inspect(links)}
    """)

    parsed_children = children_spec |> ChildrenController.parse_children()

    {:ok, state} =
      {parsed_children |> ChildrenController.check_if_children_names_unique(state), state}

    children = parsed_children |> ChildrenController.start_children()
    {:ok, state} = children |> ChildrenController.add_children(state)
    {{:ok, links}, state} = {links |> parse_links, state}
    links = links |> resolve_links(state)
    {:ok, state} = {links |> link_children(state), state}
    {children_names, children_pids} = children |> Enum.unzip()
    {:ok, state} = {children_pids |> ChildrenController.set_children_watcher(), state}
    {:ok, state} = exec_handle_spec_started(children_names, state)

    children_pids
    |> Enum.each(&change_playback_state(&1, state.playback.state))

    debug("""
    Initialized pipeline spec
    children: #{inspect(children)}
    children pids: #{inspect(children)}
    links: #{inspect(links)}
    """)

    {{:ok, children_names}, state}
  end

  @spec parse_links(Spec.links_spec_t() | any) :: Type.try_t([Link.t()])
  defp parse_links(links), do: links |> Bunch.Enum.try_map(&Link.parse/1)

  @spec resolve_links([Link.t()], State.t()) :: [Link.resolved_t()]
  defp resolve_links(links, state) do
    links
    |> Enum.map(fn %{from: from, to: to} = link ->
      %{link | from: from |> resolve_link(state), to: to |> resolve_link(state)}
    end)
  end

  defp resolve_link(%{element: element, pad_name: pad_name, id: id} = endpoint, state) do
    with {:ok, pid} <- state |> ParentState.get_child_pid(element),
         {:ok, pad_ref} <- pid |> Message.call(:get_pad_ref, [pad_name, id]) do
      %{endpoint | pid: pid, pad_ref: pad_ref}
    else
      {:error, {:unknown_child, child}} ->
        raise PipelineError, "Child #{inspect(child)} does not exist"

      {:error, {:cannot_handle_message, :unknown_pad, _ctx}} ->
        raise PipelineError, "Child #{inspect(element)} does not have pad #{inspect(pad_name)}"

      {:error, reason} ->
        raise PipelineError, """
        Error resolving pad #{inspect(pad_name)} of element #{inspect(element)}, \
        reason: #{inspect(reason, pretty: true)}\
        """
    end
  end

  # Links children based on given specification and map for mapping children
  # names into PIDs.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain linked.
  @spec link_children([Link.resolved_t()], State.t()) :: Type.try_t()
  defp link_children(links, state) do
    with :ok <- links |> Bunch.Enum.try_each(&Element.link/1),
         :ok <-
           state
           |> ParentState.get_children()
           |> Bunch.Enum.try_each(fn {_pid, pid} -> pid |> Element.handle_linking_finished() end),
         do: :ok

    :ok
  end

  @spec exec_handle_spec_started([Element.name_t()], State.t()) :: {:ok, State.t()}
  defp exec_handle_spec_started(children_names, state) do
    callback_res =
      CallbackHandler.exec_and_handle_callback(
        :handle_spec_started,
        Membrane.Pipeline,
        [children_names],
        state
      )

    with {:ok, _} <- callback_res do
      callback_res
    else
      {{:error, reason}, state} ->
        raise PipelineError, """
        Callback :handle_spec_started failed with reason: #{inspect(reason)}
        Pipeline state: #{inspect(state, pretty: true)}
        """
    end
  end
end
