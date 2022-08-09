defmodule Membrane.Core.Parent.ChildLifeController.LinkUtils do
  @moduledoc false

  use Bunch

  alias Membrane.Core.{Bin, Message, Parent, Telemetry}
  alias Membrane.Core.Bin.PadController

  alias Membrane.Core.Parent.{
    ChildLifeController,
    CrashGroup,
    Link,
    LinkParser
  }

  alias Membrane.Core.Parent.ChildLifeController
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.LinkError
  alias Membrane.Pad

  require Membrane.Core.Message
  require Membrane.Core.Telemetry
  require Membrane.Logger
  require Membrane.Pad

  @spec unlink_crash_group(CrashGroup.t(), Parent.state_t()) :: Parent.state_t()
  def unlink_crash_group(crash_group, state) do
    %CrashGroup{members: members_names} = crash_group

    Enum.reduce(members_names, state, fn member_name, state ->
      unlink_element(member_name, state)
    end)
  end

  @spec unlink_element(Membrane.Child.name_t(), Parent.state_t()) :: Parent.state_t()
  def unlink_element(child_name, state) do
    Map.update!(
      state,
      :links,
      &Map.reject(&1, fn {_id, %Link{linked?: linked?} = link} ->
        case endpoint_to_unlink(child_name, link) do
          %Endpoint{pid: pid, pad_ref: pad_ref} when linked? ->
            Message.send(pid, :handle_unlink, pad_ref)
            true

          %Endpoint{} ->
            true

          nil ->
            false
        end
      end)
    )
  end

  defp endpoint_to_unlink(child_name, %Link{from: %Endpoint{child: child_name}, to: to}), do: to

  defp endpoint_to_unlink(child_name, %Link{to: %Endpoint{child: child_name}, from: from}),
    do: from

  defp endpoint_to_unlink(_child_name, _link), do: nil

  @spec request_link(
          Membrane.Pad.direction_t(),
          Link.Endpoint.t(),
          Link.Endpoint.t(),
          ChildLifeController.spec_ref_t(),
          Link.id(),
          Parent.state_t()
        ) :: {0..2, Parent.state_t()}
  def request_link(
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

  def request_link(direction, this, _other, _spec_ref, link_id, state) do
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

  @spec resolve_links(
          [LinkParser.raw_link_t()],
          ChildLifeController.spec_ref_t(),
          Parent.state_t()
        ) :: [
          Link.t()
        ]
  def resolve_links(links, spec_ref, state) do
    Enum.map(
      links,
      &%Link{
        &1
        | spec_ref: spec_ref,
          from: resolve_endpoint(&1.from, state),
          to: resolve_endpoint(&1.to, state)
      }
    )
  end

  @spec resolve_endpoint(LinkParser.raw_endpoint_t(), Parent.state_t()) ::
          Endpoint.t() | no_return
  defp resolve_endpoint(
         %Endpoint{child: {Membrane.Bin, :itself}} = endpoint,
         %Bin.State{} = state
       ) do
    %Endpoint{pad_spec: pad_spec} = endpoint

    withl pad: {:ok, pad_info} <- Map.fetch(state.pads_info, Pad.name_by_ref(pad_spec)),
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
    child_data = Parent.ChildrenModel.get_child_data!(state, child)
    pad_name = Pad.name_by_ref(pad_spec)

    withl pad: {:ok, pad_info} <- Keyword.fetch(child_data.module.membrane_pads(), pad_name),
          ref: {:ok, ref} <- make_pad_ref(pad_spec, pad_info.availability) do
      %Endpoint{
        endpoint
        | pid: child_data.pid,
          pad_ref: ref,
          pad_info: pad_info,
          child_spec_ref: child_data.spec_ref
      }
    else
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

  @spec link(Link.t(), Parent.state_t()) :: Parent.state_t()
  def link(%Link{from: %Endpoint{child: child}, to: %Endpoint{child: child}}, _state) do
    raise LinkError, "Tried to link element #{inspect(child)} with itself"
  end

  def link(%Link{from: from, to: to} = link, state) do
    Telemetry.report_link(from, to)

    if {Membrane.Bin, :itself} in [from.child, to.child] do
      state
    else
      from_availability = Pad.availability_mode(from.pad_info.availability)
      to_availability = Pad.availability_mode(to.pad_info.availability)

      case Message.call(from.pid, :handle_link, [:output, from, to, %{initiator: :parent}]) do
        :ok ->
          put_in(state, [:links, link.id, :linked?], true)

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
