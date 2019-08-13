defmodule Membrane.Core.Bin.SpecController do
  use Bunch
  use Membrane.Log, tags: :core
  use Membrane.Core.PlaybackRequestor

  alias Membrane.{Spec, Bin, BinError}
  # TODO Link should be moved out of Pipeline
  alias Membrane.Core.Pipeline.Link

  alias Membrane.Core.{
    ChildrenController,
    ParentState,
    Message,
    Pad,
    PadController,
    CallbackHandler
  }

  alias Membrane.Core.Bin.LinkingBuffer
  alias Membrane.Element

  require Bin
  require Message

  @spec handle_spec(Spec.t(), State.t()) :: Type.stateful_try_t([Element.name_t()], State.t())
  def handle_spec(%Spec{children: children_spec, links: links}, state) do
    debug("""
    Initializing bin spec
    children: #{inspect(children_spec)}
    links: #{inspect(links)}
    """)

    parsed_children = children_spec |> ChildrenController.parse_children()

    {:ok, state} =
      {parsed_children |> ChildrenController.check_if_children_names_unique(state), state}

    children = parsed_children |> ChildrenController.start_children()
    {:ok, state} = children |> ChildrenController.add_children(state)

    {{:ok, links}, state} = {links |> parse_links, state}
    {links, state} = links |> resolve_links(state)
    {:ok, state} = links |> link_children(state)
    {children_names, children_pids} = children |> Enum.unzip()
    {:ok, state} = {children_pids |> ChildrenController.set_children_watcher(), state}
    {:ok, state} = exec_handle_spec_started(children_names, state)

    children_pids
    |> Enum.each(&change_playback_state(&1, state.playback.state))

    debug("""
    Initialized bin spec
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
    {new_links, new_state} =
      links
      |> Enum.map_reduce(
        state,
        fn link, state_acc ->
          {from, state_acc} = link.from |> resolve_link(state_acc)
          {to, state_acc} = link.to |> resolve_link(state_acc)
          new_link = %{link | from: from, to: to}
          {new_link, state_acc}
        end
      )

    {new_links, new_state}
  end

  defp resolve_link(
         %{element: Bin.this_bin_marker(), pad_name: pad_name, id: id} = endpoint,
         %{name: name} = state
       ) do
    private_pad = Pad.get_corresponding_bin_pad(pad_name)

    with {{:ok, private_pad_ref}, state} <- PadController.get_pad_ref(private_pad, id, state) do
      new_endpoint = %{endpoint | pid: self(), pad_ref: private_pad_ref, pad_name: private_pad}
      {new_endpoint, state}
    else
      {:error, :unknown_pad} ->
        raise BinError, "Bin #{inspect(name)} does not have pad #{inspect(pad_name)}"
    end
  end

  defp resolve_link(%{element: element, pad_name: pad_name, id: id} = endpoint, state) do
    with {:ok, pid} <- state |> ParentState.get_child_pid(element),
         {:ok, pad_ref} <- pid |> Message.call(:get_pad_ref, [pad_name, id]) do
      {%{endpoint | pid: pid, pad_ref: pad_ref}, state}
    else
      {:error, {:unknown_child, child}} ->
        raise BinError, "Child #{inspect(child)} does not exist"

      {:error, {:cannot_handle_message, :unknown_pad, _ctx}} ->
        raise BinError, "Child #{inspect(element)} does not have pad #{inspect(pad_name)}"

      {:error, reason} ->
        raise BinError, """
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
    debug("Linking children: links = #{inspect(links)}")

    with {:ok, state} <- links |> Bunch.Enum.try_reduce_while(state, &link/2),
         :ok <-
           state
           |> ParentState.get_children()
           |> Bunch.Enum.try_each(fn {_pid, pid} -> pid |> Element.handle_linking_finished() end),
         do: {:ok, state}
  end

  defp link(
         %Link{from: %Link.Endpoint{pid: from_pid} = from, to: %Link.Endpoint{pid: to_pid} = to},
         state
       ) do
    from_args = [
      from.pad_ref,
      :output,
      to_pid,
      to.pad_ref,
      nil,
      from.opts
    ]

    {{:ok, pad_from_info}, state} = handle_link(from.pid, from_args, state)

    state =
      if from.pid == self() do
        LinkingBuffer.eval_for_pad(state.linking_buffer, from.pad_ref, state)
        ~> %{state | linking_buffer: &1}
      else
        state
      end

    to_args = [
      to.pad_ref,
      :input,
      from_pid,
      from.pad_ref,
      pad_from_info,
      to.opts
    ]

    {_, state} = handle_link(to.pid, to_args, state)

    state =
      if to.pid == self() do
        LinkingBuffer.eval_for_pad(state.linking_buffer, to.pad_ref, state)
        ~> %{state | linking_buffer: &1}
      else
        state
      end

    {{:ok, :cont}, state}
  end

  defp handle_link(pid, args, state) do
    case self() do
      ^pid ->
        {{:ok, _spec} = res, state} = apply(PadController, :handle_link, args ++ [state])
        {:ok, state} = PadController.handle_linking_finished(state)
        {res, state}

      _ ->
        res = Message.call(pid, :handle_link, args)
        {res, state}
    end
  end

  @spec exec_handle_spec_started([Element.name_t()], State.t()) :: {:ok, State.t()}
  defp exec_handle_spec_started(children_names, state) do
    callback_res =
      CallbackHandler.exec_and_handle_callback(
        :handle_spec_started,
        Membrane.Bin,
        [children_names],
        state
      )

    with {:ok, _} <- callback_res do
      callback_res
    else
      {{:error, reason}, state} ->
        raise BinError, """
        Callback :handle_spec_started failed with reason: #{inspect(reason)}
        Pipeline state: #{inspect(state, pretty: true)}
        """
    end
  end
end
