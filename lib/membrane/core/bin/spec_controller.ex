defmodule Membrane.Core.Bin.SpecController do
  @moduledoc false
  use Bunch
  use Membrane.Log, tags: :core

  @behaviour Membrane.Core.Parent.ChildrenController

  alias Membrane.{Bin, LinkError, Pad}

  alias Membrane.Core.{
    Parent,
    Message,
    PadController
  }

  alias Membrane.Core.Bin.LinkingBuffer
  alias Membrane.Core.Link

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

  defp resolve_link(endpoint, state) do
    if endpoint.element == Bin.itself() do
      resolve_bin_link(endpoint, state)
    else
      resolve_normal_link(endpoint, state)
    end
  end

  defp resolve_bin_link(
         %{pad_name: pad_name, id: id} = endpoint,
         %{name: name} = state
       ) do
    private_pad = Pad.get_corresponding_bin_pad(pad_name)

    with {{:ok, private_pad_ref}, state} <- PadController.get_pad_ref(private_pad, id, state) do
      new_endpoint = %{endpoint | pid: self(), pad_ref: private_pad_ref, pad_name: private_pad}
      {new_endpoint, state}
    else
      {:error, :unknown_pad} ->
        raise LinkError, "Bin #{inspect(name)} does not have pad #{inspect(pad_name)}"
    end
  end

  defp resolve_normal_link(endpoint, state),
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
           |> Parent.ChildrenModel.get_children()
           |> Bunch.Enum.try_each(fn {_name, %{pid: pid}} ->
             pid |> Message.call(:linking_finished, [])
           end),
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
        LinkingBuffer.flush_for_pad(state.linking_buffer, from.pad_ref, state)
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
        LinkingBuffer.flush_for_pad(state.linking_buffer, to.pad_ref, state)
        ~> %{state | linking_buffer: &1}
      else
        state
      end

    {{:ok, :cont}, state}
  end

  defp handle_link(pid, args, state) when pid == self() do
    with {{:ok, _spec} = res, state} <- apply(PadController, :handle_link, args ++ [state]),
         {:ok, state} <- PadController.handle_linking_finished(state),
         do: {res, state}
  end

  defp handle_link(pid, args, state) do
    Message.call(pid, :handle_link, args)
    ~> {&1, state}
  end

  @impl true
  def action_handler_module, do: Membrane.Core.Bin.ActionHandler
end
