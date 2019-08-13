defmodule Membrane.Core.Bin.SpecController do
  use Bunch
  use Membrane.Log, tags: :core

  @behaviour Membrane.Core.ChildrenController

  alias Membrane.{Bin, ParentError}

  alias Membrane.Core.{
    ParentState,
    Message,
    Pad,
    PadController,
    CallbackHandler
  }

  alias Membrane.Core.Bin.LinkingBuffer
  alias Membrane.Element
  # TODO Link should be moved out of Pipeline
  alias Membrane.Core.Pipeline.Link

  require Bin
  require Message

  @impl true
  def resolve_links(links, state) do
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
        raise ParentError, "Bin #{inspect(name)} does not have pad #{inspect(pad_name)}"
    end
  end

  # This is the case of normal endpoint linking (not bin api)
  defp resolve_link(endpoint, state),
    do: {Membrane.Core.Pipeline.SpecController.resolve_link(endpoint, state), state}

  # Links children based on given specification and map for mapping children
  # names into PIDs.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain linked.
  @impl true
  def link_children(links, state) do
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

  @impl true
  def exec_handle_spec_started(children_names, state) do
    callback_res =
      CallbackHandler.exec_and_handle_callback(
        :handle_spec_started,
        Membrane.Core.Bin.ActionHandler,
        [children_names],
        state
      )

    with {:ok, _} <- callback_res do
      callback_res
    else
      {{:error, reason}, state} ->
        raise ParentError, """
        Callback :handle_spec_started failed with reason: #{inspect(reason)}
        Pipeline state: #{inspect(state, pretty: true)}
        """
    end
  end
end
