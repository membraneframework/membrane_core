defmodule Membrane.Core.Parent.ChildLifeController.LinkHandler do
  @moduledoc false

  use Bunch

  alias Membrane.Core.{Bin, Child, Message, Parent}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Parent.Link
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.LinkError
  alias Membrane.Pad

  require Membrane.Core.Message
  require Membrane.Pad

  @spec resolve_links([Parent.Link.t()], Parent.state_t()) ::
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
  @spec link_children([Parent.Link.resolved_t()], Parent.state_t()) ::
          {:ok | {:error, any}, Parent.state_t()}
  def link_children(links, state) do
    state = links |> Enum.reduce(state, &link/2)

    with :ok <- send_linking_finished(links) do
      state = Enum.reduce(links, state, &flush_linking_buffer/2)
      {:ok, state}
    end
  end

  @spec unlink_children([Link.t()], Parent.state_t()) :: {:ok | {:error, any}, Parent.state_t()}
  def unlink_children(links, state) do
    with :ok <- send_unlink(links) do
      state =
        state
        |> Map.update!(:links, &(&1 |> Enum.reject(fn link -> link in links end)))

      {:ok, state}
    end
  end

  defp flush_linking_buffer(%Link{from: from, to: to}, state) do
    state
    |> flush_linking_buffer_for_endpoint(from)
    |> flush_linking_buffer_for_endpoint(to)
  end

  defp flush_linking_buffer_for_endpoint(state, %Endpoint{
         child: {Membrane.Bin, :itself},
         pad_ref: pad
       }) do
    Bin.LinkingBuffer.flush_for_pad(pad, state)
  end

  defp flush_linking_buffer_for_endpoint(state, _endpoint) do
    state
  end

  @spec resolve_endpoint(Endpoint.t(), Parent.state_t()) ::
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

  defp get_public_pad_name(pad) do
    case pad do
      {:private, direction} -> direction
      {Membrane.Pad, {:private, direction}, ref} -> {Membrane.Pad, direction, ref}
      _pad -> pad
    end
  end

  defp report_new_link(from, to) do
    %Endpoint{child: from_child, pad_ref: from_pad} = from
    %Endpoint{child: to_child, pad_ref: to_pad} = to

    :telemetry.execute(
      Membrane.Telemetry.new_link_event_name(),
      %{
        parent_path: Membrane.ComponentPath.get_formatted(),
        from: "#{inspect(from_child)}",
        to: "#{inspect(to_child)}",
        pad_from: "#{inspect(get_public_pad_name(from_pad))}",
        pad_to: "#{inspect(get_public_pad_name(to_pad))}"
      }
    )
  end

  defp link(%Link{from: %Endpoint{child: child}, to: %Endpoint{child: child}}, _state) do
    raise LinkError, "Tried to link element #{inspect(child)} with itself"
  end

  defp link(%Link{from: from, to: to}, state) do
    report_new_link(from, to)

    {{:ok, _info}, state} =
      if from.child == {Membrane.Bin, :itself} do
        link_endpoint(:output, from, to, state)
      else
        link_endpoint(:input, to, from, state)
      end

    state
  end

  defp link_endpoint(
         direction,
         %Endpoint{child: {Membrane.Bin, :itself}} = this,
         other,
         %Bin.State{} = state
       ) do
    Child.PadController.handle_link(direction, this, other, nil, state)
  end

  defp link_endpoint(direction, this, other, state) do
    with {:ok, _info} = res <- Message.call(this.pid, :handle_link, [direction, this, other, nil]) do
      ### update link in state
      state = state |> Bunch.Struct.update_in([:links], &[%Link{from: other, to: this} | &1])

      {res, state}
    end
  end

  defp send_unlink(links) do
    links
    |> Enum.each(fn %Link{to: to} ->
      Message.send(to.pid, :handle_unlink, to.pad_ref)
    end)
  end

  defp send_linking_finished(links) do
    links
    |> Enum.flat_map(&[&1.from, &1.to])
    |> Enum.reject(&(&1.child == {Membrane.Bin, :itself}))
    |> Enum.uniq()
    |> Bunch.Enum.try_each(&Message.call(&1.pid, :linking_finished))
  end
end
