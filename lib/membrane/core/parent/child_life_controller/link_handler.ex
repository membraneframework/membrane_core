defmodule Membrane.Core.Parent.ChildLifeController.LinkHandler do
  @moduledoc false

  use Bunch
  use Membrane.Log, tags: :core

  alias Membrane.Core.{Bin, Child, Message, Parent}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Parent.{Link, State}
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.Pad
  alias Membrane.LinkError

  require Message
  require Membrane.Pad

  @spec resolve_links([Parent.Link.t()], State.t()) ::
          [Parent.Link.resolved_t()]
  def resolve_links(links, state) do
    links
    |> Enum.map(
      &%Link{&1 | from: resolve_endpoint(&1.from, state), to: resolve_endpoint(&1.to, state)}
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
           end) do
      links
      |> Enum.reduce(state, &flush_linking_buffer/2)
      ~> {:ok, &1}
    end
  end

  defp flush_linking_buffer(%Link{from: from, to: to}, state) do
    state
    |> flush_linking_buffer_for_endpoint(from)
    |> flush_linking_buffer_for_endpoint(to)
  end

  defp flush_linking_buffer_for_endpoint(state, %Endpoint{
         element: {Membrane.Bin, :itself},
         pad_ref: pad
       }) do
    Bin.LinkingBuffer.flush_for_pad(pad, state)
  end

  defp flush_linking_buffer_for_endpoint(state, _) do
    state
  end

  @spec resolve_endpoint(Endpoint.t(), State.t()) ::
          Endpoint.resolved_t() | no_return
  defp resolve_endpoint(
         %Endpoint{child: {Membrane.Bin, :itself}} = endpoint,
         %Bin.State{} = state
       ) do
    %Endpoint{pad_spec: pad_spec} = endpoint
    priv_pad_spec = Membrane.Pad.get_corresponding_bin_pad(pad_spec)

    withl pad: {:ok, priv_info} <- state.pads.info |> Map.fetch(Pad.name_by_ref(priv_pad_spec)),
          do: dynamic? = Pad.is_availability_dynamic(priv_info.availability),
          name: false <- dynamic? and Pad.is_pad_name(pad_spec),
          link: true <- not dynamic? or :ok == PadModel.assert_instance(state, pad_spec),
          ref: {:ok, ref} <- make_pad_ref(priv_pad_spec, priv_info.availability) do
      %Endpoint{endpoint | pid: self(), pad_ref: ref, pad_spec: priv_pad_spec}
    else
      pad: :error ->
        raise LinkError, "Bin #{inspect(state.name)} does not have pad #{inspect(pad_spec)}"

      name: true ->
        raise LinkError,
              "Exact reference not passed when linking dynamic bin pad #{inspect(pad_spec)}"

      link: false ->
        raise LinkError,
              "Linking dynamic bin pad #{inspect(pad_spec)} when it is not yet externally linked"

      ref: {:error, :invalid_availability} ->
        raise LinkError,
              "Dynamic pad ref #{inspect(pad_spec)} passed for static pad of bin #{
                inspect(state.name)
              }"
    end
  end

  defp resolve_endpoint(endpoint, state) do
    %Endpoint{child: child, pad_spec: pad_spec} = endpoint

    withl child: {:ok, child_data} <- state |> Parent.ChildrenModel.get_child_data(child),
          do: pad_name = Pad.name_by_ref(pad_spec),
          pad: {:ok, pad_info} <- child_data.module.membrane_pads() |> Keyword.fetch(pad_name),
          ref: {:ok, ref} <- make_pad_ref(pad_spec, pad_info.availability) do
      %Endpoint{endpoint | pid: child_data.pid, pad_ref: ref}
    else
      child: {:error, {:unknown_child, _child}} ->
        raise LinkError, "Child #{inspect(child)} does not exist"

      pad: :error ->
        raise LinkError, "Child #{inspect(child)} does not have pad #{inspect(pad_spec)}"

      ref: {:error, :invalid_availability} ->
        raise LinkError,
              "Dynamic pad ref #{inspect(pad_spec)} passed for static pad of child #{
                inspect(child)
              }"
    end
  end

  defp make_pad_ref(pad_spec, availability) do
    case {pad_spec, Pad.availability_mode(availability)} do
      {Pad.ref(_name, _id), :static} -> {:error, :invalid_availability}
      {name, :static} -> {:ok, name}
      {Pad.ref(_name, _id) = ref, :dynamic} -> {:ok, ref}
      {name, :dynamic} -> {:ok, Pad.ref(name, make_ref())}
    end
  end

  defp link(%Link{from: %Endpoint{child: child}, to: %Endpoint{child: child}}, _state) do
    raise LinkError, "Tried to link element #{inspect(child)} with itself"
  end

  defp link(%Link{from: from, to: to}, state) do
    {{:ok, info}, state} = link_endpoint(:output, from, to, nil, state)
    {{:ok, _info}, state} = link_endpoint(:input, to, from, info, state)
    state
  end

  defp link_endpoint(
         direction,
         %Endpoint{child: {Membrane.Bin, :itself}} = this,
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
             this.pad_props,
             state
           ) do
      {{:ok, info}, state}
    end
  end

  defp link_endpoint(direction, this, other, other_info, state) do
    Message.call(this.pid, :handle_link, [
      this.pad_ref,
      direction,
      other.pid,
      other.pad_ref,
      other_info,
      this.pad_props
    ])
    ~> {&1, state}
  end
end
