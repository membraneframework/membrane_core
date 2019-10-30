defmodule Membrane.Core.Parent.ChildLifeController.LinkHandler do
  @moduledoc false

  use Bunch
  use Membrane.Log, tags: :core

  alias Membrane.Core.{Bin, Child, Message, Parent}
  alias Membrane.Core.Parent.{Link, State}
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.{ParentError, LinkError}

  require Message

  @spec resolve_links([Parent.Link.t()], State.t()) ::
          {[Parent.Link.resolved_t()], State.t()}
  def resolve_links(links, state) do
    links
    |> Enum.map_reduce(
      state,
      fn link, state_acc ->
        {from, state_acc} = link.from |> resolve_endpoint(state_acc)
        {to, state_acc} = link.to |> resolve_endpoint(state_acc)
        new_link = %{link | from: from, to: to}
        {new_link, state_acc}
      end
    )
  end

  # Links children based on given specification and map for mapping children
  # names into PIDs.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain linked.
  @spec link_children([Parent.Link.resolved_t()], State.t()) ::
          {:ok | {:error, any}, State.t()}
  def link_children(links, state) do
    state = links |> Enum.reduce(state, &link/2)

    with :ok <-
           state
           |> Parent.ChildrenModel.get_children()
           |> Bunch.Enum.try_each(fn {_name, %{pid: pid}} ->
             pid |> Message.call(:linking_finished, [])
           end),
         do: {:ok, state}
  end

  @spec resolve_endpoint(Endpoint.t(), State.t()) ::
          {Endpoint.resolved_t(), State.t()} | no_return
  defp resolve_endpoint(
         %Endpoint{element: {Membrane.Bin, :itself}} = endpoint,
         %Bin.State{} = state
       ) do
    %Endpoint{pad_name: pad_name, id: id} = endpoint
    private_name = Membrane.Pad.get_corresponding_bin_pad(pad_name)

    withl pad: {:ok, pad} <- state.pads.info |> Map.fetch(private_name),
          ref: {:ok, ref} <- Membrane.Pad.make_pad_ref(private_name, id, pad.availability) do
      %Endpoint{endpoint | pid: self(), pad_ref: ref, pad_name: private_name}
      ~> {&1, state}
    else
      pad: :error ->
        raise LinkError, "Bin #{inspect(state.name)} does not have pad #{inspect(pad_name)}"

      ref: {:error, :invalid_availability} ->
        raise ParentError,
              "Pad id passed for static pad #{inspect(pad_name)} of bin #{inspect(state.name)}"
    end
  end

  defp resolve_endpoint(endpoint, state) do
    %Endpoint{element: child, pad_name: pad_name, id: id} = endpoint

    withl child: {:ok, child_data} <- state |> Parent.ChildrenModel.get_child_data(child),
          pad: {:ok, pad} <- child_data.module.membrane_pads() |> Keyword.fetch(pad_name),
          ref: {:ok, ref} <- Membrane.Pad.make_pad_ref(pad_name, id, pad.availability) do
      {%Endpoint{endpoint | pid: child_data.pid, pad_ref: ref}, state}
    else
      child: {:error, {:unknown_child, _child}} ->
        raise ParentError, "Child #{inspect(child)} does not exist"

      pad: :error ->
        raise ParentError, "Child #{inspect(child)} does not have pad #{inspect(pad_name)}"

      ref: {:error, :invalid_availability} ->
        raise ParentError,
              "Pad id passed for static pad #{inspect(pad_name)} of child #{inspect(child)}"
    end
  end

  defp link(%Link{from: %Endpoint{pid: pid}, to: %Endpoint{pid: pid}}, _state) do
    raise LinkError, "Cannot link element with itself"
  end

  defp link(%Link{from: from, to: to}, state) do
    {{:ok, info}, state} = link_endpoint(:output, from, to, nil, state)
    {{:ok, _info}, state} = link_endpoint(:input, to, from, info, state)
    state
  end

  defp link_endpoint(
         direction,
         %Endpoint{element: {Membrane.Bin, :itself}} = this,
         other,
         other_info,
         %Bin.State{} = state
       ) do
    with {{:ok, info}, state} <-
           Child.PadController.handle_link(
             this.pad_ref,
             direction,
             other.pid,
             other.pad_ref,
             other_info,
             this.opts,
             state
           ) do
      Bin.LinkingBuffer.flush_for_pad(state.linking_buffer, this.pad_ref, state)
      ~> %{state | linking_buffer: &1}
      ~> {{:ok, info}, &1}
    end
  end

  defp link_endpoint(direction, this, other, other_info, state) do
    Message.call(this.pid, :handle_link, [
      this.pad_ref,
      direction,
      other.pid,
      other.pad_ref,
      other_info,
      this.opts
    ])
    ~> {&1, state}
  end
end
