defmodule Membrane.Core.Parent.ChildLifeController.LinkHandler do
  @moduledoc false

  use Bunch

  alias Membrane.Core.{Bin, Message, Parent, Pipeline, Telemetry}
  alias Membrane.Core.Bin.PadController
  alias Membrane.Core.Parent.ChildLifeController.StartupHandler
  alias Membrane.Core.Parent.{CrashGroup, Link, LinkParser}
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.LinkError
  alias Membrane.Pad

  require Membrane.Core.Message
  require Membrane.Core.Telemetry
  require Membrane.Logger
  require Membrane.Pad

  def init_spec_linking(spec_ref, links, state) do
    links = resolve_links(links, state)

    {links, state} =
      Enum.map_reduce(links, state, fn link, state ->
        link_id = {spec_ref, make_ref()}

        {to_respond_from, state} =
          request_link(:output, link.from, link.to, spec_ref, link_id, state)

        {to_respond_to, state} =
          request_link(:input, link.to, link.from, spec_ref, link_id, state)

        {{link_id, %{link: link, to_respond: to_respond_from + to_respond_to}}, state}
      end)

    state =
      put_in(state, [:pending_specs, spec_ref], %{
        links: Map.new(links),
        status: :linking_internally
      })

    proceed_spec_linking(spec_ref, state)
  end

  def proceed_spec_linking(spec_ref, state) do
    spec_data = Map.fetch!(state.pending_specs, spec_ref)
    {spec_data, state} = do_proceed_spec_linking(spec_ref, spec_data, state)
    put_in(state, [:pending_specs, spec_ref], spec_data)
  end

  defp do_proceed_spec_linking(spec_ref, %{status: :linking_internally} = spec_data, state) do
    if spec_data.links |> Map.values() |> Enum.all?(&(&1.to_respond == 0)) do
      {:ok, state} =
        spec_data.links
        |> Map.values()
        |> Enum.map(& &1.link)
        |> Enum.reject(&({Membrane.Bin, :itself} in [&1.from.child, &1.to.child]))
        |> link_children(state)

      Membrane.Logger.debug("Spec #{inspect(spec_ref)} linked internally")
      do_proceed_spec_linking(spec_ref, %{spec_data | status: :linked_internally}, state)
    else
      {spec_data, state}
    end
  end

  defp do_proceed_spec_linking(
         spec_ref,
         %{status: :linked_internally} = spec_data,
         %Pipeline.State{} = state
       ) do
    do_proceed_spec_linking(spec_ref, %{spec_data | status: :linked}, state)
  end

  defp do_proceed_spec_linking(
         spec_ref,
         %{status: :linked_internally} = spec_data,
         %Bin.State{} = state
       ) do
    state = PadController.respond_links(spec_ref, state)
    Membrane.Logger.debug("Linking spec #{inspect(spec_ref)} externally")
    do_proceed_spec_linking(spec_ref, %{spec_data | status: :linking_externally}, state)
  end

  defp do_proceed_spec_linking(
         spec_ref,
         %{status: :linking_externally} = spec_data,
         %Bin.State{} = state
       ) do
    if PadController.all_pads_linked?(spec_ref, state) do
      Membrane.Logger.debug("Spec #{inspect(spec_ref)} linked externally")
      do_proceed_spec_linking(spec_ref, %{spec_data | status: :linked}, state)
    else
      {spec_data, state}
    end
  end

  defp do_proceed_spec_linking(spec_ref, %{status: :linked} = spec_data, state) do
    state = StartupHandler.init_playback_state(spec_ref, state)
    {spec_data, state}
  end

  def handle_link_response(link_id, state) do
    {spec_ref, _link_ref} = link_id
    state = update_in(state, [:pending_specs, spec_ref, :links, link_id, :to_respond], &(&1 - 1))
    proceed_spec_linking(spec_ref, state)
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

  @spec resolve_links([LinkParser.raw_link_t()], Parent.state_t()) ::
          [Parent.Link.t()]
  defp resolve_links(links, state) do
    Enum.map(
      links,
      &%Link{&1 | from: resolve_endpoint(&1.from, state), to: resolve_endpoint(&1.to, state)}
    )
  end

  defp request_link(
         _direction,
         %Link.Endpoint{child: {Membrane.Bin, :itself}} = this,
         other,
         spec_ref,
         _link_id,
         state
       ) do
    state = PadController.handle_internal_link_request(this.pad_ref, other, spec_ref, state)
    {0, state}
  end

  defp request_link(direction, this, _other, _spec_ref, link_id, state) do
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
  defp link_children(links, state) do
    state = Enum.reduce(links, state, &link/2)
    {:ok, state}
  end

  @spec resolve_endpoint(LinkParser.raw_endpoint_t(), Parent.state_t()) ::
          Endpoint.t() | no_return
  defp resolve_endpoint(
         %Endpoint{child: {Membrane.Bin, :itself}} = endpoint,
         %Bin.State{} = state
       ) do
    %Endpoint{pad_spec: pad_spec} = endpoint

    withl pad: {:ok, pad_info} <- Map.fetch(state.pads.info, Pad.name_by_ref(pad_spec)),
          ref: {:ok, ref} <- make_pad_ref(pad_spec, pad_info.availability, true) do
      %Endpoint{endpoint | pid: self(), pad_ref: ref}
    else
      pad: :error ->
        raise LinkError, "Bin #{inspect(state.name)} does not have pad #{inspect(pad_spec)}"

      ref: {:error, :invalid_availability} ->
        raise LinkError,
              "Dynamic pad ref #{inspect(pad_spec)} passed for static pad of bin #{inspect(state.name)}"

      ref: {:error, :no_exact_reference} ->
        raise LinkError,
              "Exact reference not passed when linking dynamic pad #{inspect(pad_spec)} of bin #{inspect(state.name)}"
    end
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

  defp make_pad_ref(pad_spec, availability, bin_internal? \\ false) do
    case {pad_spec, Pad.availability_mode(availability)} do
      {Pad.ref(_name, _id), :static} -> {:error, :invalid_availability}
      {name, :static} -> {:ok, name}
      {Pad.ref(_name, _id) = ref, :dynamic} -> {:ok, ref}
      {_name, :dynamic} when bin_internal? -> {:error, :no_exact_reference}
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
