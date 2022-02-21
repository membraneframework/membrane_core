defmodule Membrane.Core.Parent.ChildLifeController.LinkHandler do
  @moduledoc false

  # Module responsible for linking children.
  #
  # The linking process consists of the following phases:
  # - Internal linking - link requests are sent to all the children involved. After receiving link responses
  #   for each link, the actual linking (sending `:handle_link` messages) happens. When all children are
  #   linked, proceed to the next phase.
  # - External linking - only for bins. Responding to link requests sent to bin and proxying linking messages
  #   to the proper children. When all the messages are proxied, proceed to the next phase.
  # - Linking finished - Playback state of all the new children of the spec is initialized.

  use Bunch

  alias Membrane.Core.{Bin, Message, Parent, Pipeline, Telemetry}
  alias Membrane.Core.Bin.PadController
  alias Membrane.Core.Parent.{ChildLifeController, CrashGroup, Link, LinkParser}
  alias Membrane.Core.Parent.ChildLifeController.StartupHandler
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.LinkError
  alias Membrane.Pad

  require Membrane.Core.Message
  require Membrane.Core.Telemetry
  require Membrane.Logger
  require Membrane.Pad

  @type link_id_t :: {ChildLifeController.spec_ref_t(), reference()}

  @type pending_spec_t :: %{
          status: :linking_internally | :linking_externally | :linked,
          links: %{link_id_t => %{link: Parent.Link.t(), awaiting_responses: non_neg_integer()}}
        }

  @type pending_specs_t :: %{ChildLifeController.spec_ref_t() => pending_spec_t()}

  @type state_t :: Pipeline.State.t() | Bin.State.t()

  @spec init_spec_linking(ChildLifeController.spec_ref_t(), [LinkParser.raw_link_t()], state_t()) ::
          state_t()
  def init_spec_linking(spec_ref, links, state) do
    Process.send_after(self(), Message.new(:spec_linking_timeout, spec_ref), 5000)

    {links, state} =
      Enum.map_reduce(links, state, fn link, state ->
        link = %Link{
          link
          | from: resolve_endpoint(link.from, state),
            to: resolve_endpoint(link.to, state)
        }

        link_id = {spec_ref, make_ref()}

        {awaiting_responses_from, state} =
          request_link(:output, link.from, link.to, spec_ref, link_id, state)

        {awaiting_responses_to, state} =
          request_link(:input, link.to, link.from, spec_ref, link_id, state)

        {{link_id,
          %{link: link, awaiting_responses: awaiting_responses_from + awaiting_responses_to}},
         state}
      end)

    state =
      put_in(state, [:pending_specs, spec_ref], %{
        links: Map.new(links),
        status: :linking_internally
      })

    proceed_spec_linking(spec_ref, state)
  end

  @spec handle_spec_timeout(ChildLifeController.spec_ref_t(), state_t()) :: state_t()
  def handle_spec_timeout(spec_ref, state) do
    {spec_data, state} = pop_in(state, [:pending_specs, spec_ref])

    unless spec_data.status == :linked do
      raise LinkError,
            "Spec #{inspect(spec_ref)} linking took too long, spec_data: #{inspect(spec_data, pretty: true)}"
    end

    state
  end

  @spec proceed_spec_linking(ChildLifeController.spec_ref_t(), state_t()) :: state_t()
  def proceed_spec_linking(spec_ref, state) do
    spec_data = Map.fetch!(state.pending_specs, spec_ref)
    {spec_data, state} = do_proceed_spec_linking(spec_ref, spec_data, state)
    put_in(state, [:pending_specs, spec_ref], spec_data)
  end

  defp do_proceed_spec_linking(spec_ref, %{status: :linking_internally} = spec_data, state) do
    links = spec_data.links |> Map.values()

    if Enum.all?(links, &(&1.awaiting_responses == 0)) do
      state = links |> Enum.map(& &1.link) |> Enum.reduce(state, &link/2)
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

  @spec handle_link_response(link_id_t(), state_t()) :: state_t()
  def handle_link_response(link_id, state) do
    {spec_ref, _link_ref} = link_id

    state =
      update_in(
        state,
        [:pending_specs, spec_ref, :links, link_id, :awaiting_responses],
        &(&1 - 1)
      )

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
    if Map.fetch!(state.children, this.child).component_type == :bin do
      Message.send(this.pid, :link_request, [
        this.pad_ref,
        direction,
        link_id,
        this.pad_props.options
      ])

      {1, state}
    else
      {0, state}
    end
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
      %Endpoint{endpoint | pid: child_data.pid, pad_ref: ref, pad_info: pad_info}
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
    Telemetry.report_link(from, to)

    if {Membrane.Bin, :itself} in [from.child, to.child] do
      state
    else
      from_availability = Pad.availability_mode(from.pad_info.availability)
      to_availability = Pad.availability_mode(to.pad_info.availability)

      case Message.call(from.pid, :handle_link, [:output, from, to, %{initiator: :parent}]) do
        :ok ->
          update_in(state, [:links], &[%Link{from: from, to: to} | &1])

        {:error, {:call_failure, _reason}} when to_availability == :static ->
          Process.exit(to.pid, :kill)
          state

        {:error, {:neighbor_dead, _reason}} when from_availability == :static ->
          Process.exit(from.pid, :kill)
          state

        {:error, {:call_failure, _reason}} when to_availability == :dynamic ->
          Membrane.Logger.debug("""
          Failed to establish link between #{inspect(from.pad_ref)} and #{inspect(to.pad_ref)}
          because #{inspect(from.child)} is down.
          """)

          state

        {:error, {:neighbor_dead, _reason}} when from_availability == :dynamic ->
          Membrane.Logger.debug("""
          Failed to establish link between #{inspect(from.pad_ref)} and #{inspect(to.pad_ref)}
          because #{inspect(to.child)} is down.
          """)

          state
      end
    end
  end
end
