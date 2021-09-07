defmodule Membrane.Core.Parent.ChildLifeController.LinkHandler do
  @moduledoc false

  use Bunch

  alias Membrane.Core.{Bin, Child, Message, Parent, Telemetry}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Parent.{CrashGroup, Link, LinkParser}
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.LinkError
  alias Membrane.Pad

  require Membrane.Core.Message
  require Membrane.Core.Telemetry
  require Membrane.Pad

  @spec resolve_links([LinkParser.raw_link_t()], Parent.state_t()) ::
          [Parent.Link.t()]
  def resolve_links(links, state) do
    Enum.map(
      links,
      &%Link{&1 | from: resolve_endpoint(&1.from, state), to: resolve_endpoint(&1.to, state)}
    )
  end

  def request_links(links, spec_ref, state) do
    Enum.reduce(links, state, fn link, state ->
      link_id = make_ref()

      {to_respond_from, state} =
        do_request_link(:output, link.from, link.to, spec_ref, link_id, state)

      {to_respond_to, state} =
        do_request_link(:input, link.to, link.from, spec_ref, link_id, state)

      put_in(state, [:pending_links, link_id], %{
        link: link,
        spec_ref: spec_ref,
        to_respond: to_respond_from + to_respond_to
      })
    end)
  end

  defp do_request_link(
         _direction,
         %Link.Endpoint{child: {Membrane.Bin, :itself}} = this,
         other,
         spec_ref,
         _link_id,
         state
       ) do
    state =
      PadModel.update_data!(
        state,
        this.pad_ref,
        &%{&1 | endpoint: other, spec_ref: spec_ref}
      )

    {0, state}
  end

  defp do_request_link(direction, this, _other, _spec_ref, link_id, state) do
    Message.send(this.pid, :link_request, [this.pad_ref, direction, link_id, this.pad_props])
    {1, state}
  end

  # Links children based on given specification and map for mapping children
  # names into PIDs.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain linked.
  @spec link_children([Parent.Link.t()], Parent.state_t()) ::
          {:ok | {:error, any}, Parent.state_t()}
  def link_children(links, state) do
    state = Enum.reduce(links, state, &link/2)
    {:ok, state}
  end

  @spec unlink_crash_group(CrashGroup.t(), Parent.state_t()) :: Parent.state_t()
  def unlink_crash_group(crash_group, state) do
    %CrashGroup{members: members_names} = crash_group

    links_to_remove =
      Enum.filter(state.links, fn %Link{from: from, to: to} ->
        from.child in members_names or to.child in members_names
      end)

    Enum.each(links_to_remove, fn %Link{to: to, from: from} ->
      cond do
        from.child not in members_names -> Message.send(from.pid, :handle_unlink, from.pad_ref)
        to.child not in members_names -> Message.send(to.pid, :handle_unlink, to.pad_ref)
        true -> :ok
      end
    end)

    Map.update!(state, :links, &Enum.reject(&1, fn link -> link in links_to_remove end))
  end

  @spec resolve_endpoint(LinkParser.raw_endpoint_t(), Parent.state_t()) ::
          Endpoint.t() | no_return
  defp resolve_endpoint(
         %Endpoint{child: {Membrane.Bin, :itself}} = endpoint,
         %Bin.State{} = state
       ) do
    # %Endpoint{pad_spec: pad_spec} = endpoint
    # priv_pad_spec = Membrane.Pad.get_corresponding_bin_pad(pad_spec)

    # withl pad: {:ok, priv_info} <- Map.fetch(state.pads.info, Pad.name_by_ref(priv_pad_spec)),
    #       do: dynamic? = Pad.is_availability_dynamic(priv_info.availability),
    #       name: false <- dynamic? and Pad.is_pad_name(pad_spec),
    #       link: true <- not dynamic? or :ok == PadModel.assert_instance(state, pad_spec),
    #       ref: {:ok, ref} <- make_pad_ref(priv_pad_spec, priv_info.availability) do
    #   %Endpoint{endpoint | pid: self(), pad_ref: ref, pad_spec: priv_pad_spec}
    # else
    #   pad: :error ->
    #     raise LinkError, "Bin #{inspect(state.name)} does not have pad #{inspect(pad_spec)}"

    #   name: true ->
    #     raise LinkError,
    #           "Exact reference not passed when linking dynamic bin pad #{inspect(pad_spec)}"

    #   link: false ->
    #     raise LinkError,
    #           "Linking dynamic bin pad #{inspect(pad_spec)} when it is not yet externally linked"

    #   ref: {:error, :invalid_availability} ->
    #     raise LinkError,
    #           "Dynamic pad ref #{inspect(pad_spec)} passed for static pad of bin #{inspect(state.name)}"
    # end
    {:ok, pad_info} = Map.fetch(state.pads.info, Pad.name_by_ref(endpoint.pad_spec))
    {:ok, pad_ref} = make_pad_ref(endpoint.pad_spec, pad_info.availability)
    %Endpoint{endpoint | pid: self(), pad_ref: pad_ref}
  end

  defp resolve_endpoint(endpoint, state) do
    %Endpoint{child: child, pad_spec: pad_spec} = endpoint

    withl child: {:ok, child_data} <- Parent.ChildrenModel.get_child_data(state, child),
          do: pad_name = Pad.name_by_ref(pad_spec),
          pad: {:ok, pad_info} <- Keyword.fetch(child_data.module.membrane_pads(), pad_name),
          ref: {:ok, ref} <- make_pad_ref(pad_spec, pad_info.availability) do
      %Endpoint{endpoint | pid: child_data.pid, pad_ref: ref}
    else
      child: {:error, {:unknown_child, _child}} ->
        raise LinkError, "Child #{inspect(child)} does not exist"

      pad: :error ->
        raise LinkError, "Child #{inspect(child)} does not have pad #{inspect(pad_spec)}"

      ref: {:error, :invalid_availability} ->
        raise LinkError,
              "Dynamic pad ref #{inspect(pad_spec)} passed for static pad of child #{inspect(child)}"
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
<<<<<<< HEAD
    Telemetry.report_link(from, to)
    do_link(from, to, state)
  end

  # If the link involves the bin itself, make sure to call `handle_link` in the bin, to avoid
  # calling self() or calling a child that would call the bin, making a deadlock.
  defp do_link(%Endpoint{child: {Membrane.Bin, :itself}} = from, to, %Bin.State{} = state) do
    {{:ok, _info}, state} = Child.PadController.handle_link(:output, from, to, nil, state)
    state
  end

  defp do_link(from, %Endpoint{child: {Membrane.Bin, :itself}} = to, %Bin.State{} = state) do
    {{:ok, _info}, state} = Child.PadController.handle_link(:input, to, from, nil, state)
    state
  end

  defp do_link(from, to, state) do
    {:ok, _info} = Message.call(from.pid, :handle_link, [:output, from, to, nil])
    state = Bunch.Access.update_in(state, [:links], &[%Link{from: from, to: to} | &1])
    state
  end

  defp send_linking_finished(links) do
    links
    |> Enum.flat_map(&[&1.from, &1.to])
    |> Enum.reject(&(&1.child == {Membrane.Bin, :itself}))
    |> Enum.uniq()
    |> Bunch.Enum.try_each(&Message.call(&1.pid, :linking_finished))
=======
    Telemetry.report_new_link(from, to)
    {:ok, _info} = Message.call(from.pid, :handle_link, [:output, from, to, nil, nil])
    Bunch.Access.update_in(state, [:links], &[%Link{from: from, to: to} | &1])
>>>>>>> 519c051f (refactor pad linking)
  end
end
