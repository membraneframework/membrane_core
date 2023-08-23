defmodule Membrane.Core.Parent.ChildLifeController.LinkUtils do
  @moduledoc false

  use Bunch

  alias Membrane.Child
  alias Membrane.Core.{Bin, Message, Parent, Telemetry}
  alias Membrane.Core.Bin.PadController

  alias Membrane.Core.Parent.{
    ChildLifeController,
    CrashGroup,
    Link,
    SpecificationParser
  }

  alias Membrane.Core.Parent.ChildLifeController
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.LinkError
  alias Membrane.Pad
  alias Membrane.ParentError

  require Membrane.Core.Message
  require Membrane.Core.Telemetry
  require Membrane.Logger
  require Membrane.Pad

  @spec unlink_crash_group(CrashGroup.t(), Parent.state()) :: Parent.state()
  def unlink_crash_group(crash_group, state) do
    %CrashGroup{members: members_names} = crash_group

    Enum.reduce(members_names, state, fn member_name, state ->
      with %{children: %{^member_name => _data}} <- state do
        unlink_element(member_name, state)
      end
    end)
  end

  @spec handle_child_pad_removed(Child.name(), Pad.ref(), Parent.state()) :: Parent.state()
  def handle_child_pad_removed(child, pad, state) do
    {:ok, link} = get_link(child, pad, state)

    state =
      opposite_endpoint(link, child)
      |> case do
        %Endpoint{child: {Membrane.Bin, :itself}} = bin_endpoint ->
          PadController.remove_pad(bin_endpoint.pad_ref, state)

        %Endpoint{} = endpoint ->
          Message.send(endpoint.pid, :handle_unlink, endpoint.pad_ref)
          state
      end

    ChildLifeController.remove_link_from_specs(link.id, state)
    |> Map.update!(:links, &Map.delete(&1, link.id))
  end

  @spec remove_link(Child.name(), Pad.ref(), Parent.state()) :: Parent.state()
  def remove_link(child_name, pad_ref, state) do
    with {:ok, link} <- get_link(child_name, pad_ref, state) do
      state =
        [link.to, link.from]
        |> Enum.reduce(state, &unlink_endpoint/2)

      ChildLifeController.remove_link_from_specs(link.id, state)
      |> Map.update!(:links, &Map.delete(&1, link.id))
    else
      {:error, :not_found} ->
        with %{^child_name => _child_entry} <- state.children do
          raise ParentError, """
          Attempted to unlink pad #{inspect(pad_ref)} of child #{inspect(child_name)}, but this child does not have this pad linked
          """
        end

        raise ParentError, """
        Attempted to unlink pad #{inspect(pad_ref)} of child #{inspect(child_name)}, but such a child does not exist
        """
    end
  end

  @spec unlink_element(Child.name(), Parent.state()) :: Parent.state()
  def unlink_element(child_name, state) do
    {dropped_links, links} =
      state.links
      |> Map.values()
      |> Enum.split_with(&(child_name in [&1.from.child, &1.to.child]))

    state = %{state | links: Map.new(links, &{&1.id, &1})}

    Enum.reduce(dropped_links, state, fn link, state ->
      endpoint_to_unlink(child_name, link)
      |> unlink_endpoint(state)
    end)
  end

  defp unlink_endpoint(%Endpoint{child: {Membrane.Bin, :itself}} = endpoint, state) do
    PadController.remove_pad(endpoint.pad_ref, state)
  end

  defp unlink_endpoint(%Endpoint{} = endpoint, state) do
    Message.send(endpoint.pid, :handle_unlink, endpoint.pad_ref)
    state
  end

  defp endpoint_to_unlink(child_name, %Link{from: %Endpoint{child: child_name}, to: to}), do: to

  defp endpoint_to_unlink(child_name, %Link{to: %Endpoint{child: child_name}, from: from}),
    do: from

  defp endpoint_to_unlink(_child_name, _link), do: nil

  @spec request_link(
          Membrane.Pad.direction(),
          Link.Endpoint.t(),
          Link.Endpoint.t(),
          ChildLifeController.spec_ref(),
          Link.id(),
          Parent.state()
        ) :: {[{Link.id(), Membrane.Pad.direction()}], Parent.state()}
  def request_link(
        _direction,
        %Link.Endpoint{child: {Membrane.Bin, :itself}} = this,
        other,
        spec_ref,
        _link_id,
        state
      ) do
    state = PadController.handle_internal_link_request(this.pad_ref, other, spec_ref, state)
    {[], state}
  end

  def request_link(direction, this, _other, _spec_ref, link_id, state) do
    if Map.fetch!(state.children, this.child).component_type == :bin do
      Message.send(this.pid, :link_request, [
        this.pad_ref,
        direction,
        link_id,
        this.pad_props.options
      ])

      {[{link_id, direction}], state}
    else
      {[], state}
    end
  end

  @spec resolve_links(
          [SpecificationParser.raw_link()],
          ChildLifeController.spec_ref(),
          Parent.state()
        ) :: [
          Link.t()
        ]
  def resolve_links(links, spec_ref, state) do
    links =
      Enum.map(
        links,
        &%Link{
          &1
          | spec_ref: spec_ref,
            from: resolve_endpoint(&1.from, state),
            to: resolve_endpoint(&1.to, state)
        }
      )

    :ok = validate_links(links, state)

    links
  end

  @spec get_link(Child.name(), Pad.ref(), Parent.state()) ::
          {:ok, Link.t()} | {:error, :not_found}
  def get_link(child, child_pad_ref, state) do
    Enum.find(state.links, fn {_id, link} ->
      [link.from, link.to]
      |> Enum.any?(&(&1.child == child and &1.pad_ref == child_pad_ref))
    end)
    |> case do
      {_id, %Link{} = link} -> {:ok, link}
      nil -> {:error, :not_found}
    end
  end

  defp opposite_endpoint(%Link{from: %Endpoint{child: child}, to: to}, child), do: to

  defp opposite_endpoint(%Link{to: %Endpoint{child: child}, from: from}, child), do: from

  defp validate_links(links, state) do
    links
    |> Enum.concat(Map.values(state.links))
    |> Enum.flat_map(&[&1.from, &1.to])
    |> Enum.map(&{&1.child, &1.pad_ref})
    |> Bunch.Enum.duplicates()
    |> case do
      [] ->
        :ok

      duplicates ->
        inspected_duplicated_pads =
          Enum.map_join(duplicates, ", ", fn {child, pad_ref} ->
            "pad #{inspect(pad_ref)} of child #{inspect(child)}"
          end)

        raise LinkError, """
        Attempted to link the following pads more than once: #{inspected_duplicated_pads}
        """
    end

    :ok
  end

  @spec resolve_endpoint(SpecificationParser.raw_endpoint(), Parent.state()) ::
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

  @spec link(Link.t(), Parent.state()) :: Parent.state()
  def link(%Link{from: %Endpoint{child: child}, to: %Endpoint{child: child}}, _state) do
    raise LinkError, "Tried to link element #{inspect(child)} with itself"
  end

  def link(%Link{from: from, to: to} = link, state) do
    Telemetry.report_link(from, to)

    if {Membrane.Bin, :itself} in [from.child, to.child] do
      state
    else
      params = %{stream_format_validation_params: []}

      case Message.call(from.pid, :handle_link, [:output, from, to, params]) do
        :ok ->
          put_in(state, [:links, link.id, :linked?], true)

        {:error, reason} ->
          log_handle_link_error(reason, from, to)

          for endpoint <- [from, to] do
            Message.send(endpoint.pid, :handle_unlink, endpoint.pad_ref)
          end

          state
      end
    end
  end

  defp log_handle_link_error({:call_failure, _reason}, from, to) do
    Membrane.Logger.debug("""
    Failed to establish link between #{inspect(from.child)} via #{inspect(from.pad_ref)} and
    #{inspect(to.child)} via #{inspect(to.pad_ref)} because #{inspect(from.child)} is down.
    """)
  end

  defp log_handle_link_error({:neighbor_dead, _reason}, from, to) do
    Membrane.Logger.debug("""
    Failed to establish link between #{inspect(from.child)} via #{inspect(from.pad_ref)} and
    #{inspect(to.child)} via #{inspect(to.pad_ref)} because #{inspect(to.child)} is down.
    """)
  end

  defp log_handle_link_error({:child_dead, _reason}, from, to) do
    Membrane.Logger.debug("""
    Failed to establish link between #{inspect(from.child)} via #{inspect(from.pad_ref)} and
    #{inspect(to.child)} via #{inspect(to.pad_ref)} because descendant of #{inspect(from.child)}
    is down.
    """)
  end

  defp log_handle_link_error({:neighbor_child_dead, _reason}, from, to) do
    Membrane.Logger.debug("""
    Failed to establish link between #{inspect(from.child)} via #{inspect(from.pad_ref)} and
    #{inspect(to.child)} via #{inspect(to.pad_ref)} because descendant of #{inspect(to.child)}
    is down.
    """)
  end

  defp log_handle_link_error({:unknown_pad, name, pad_ref}, from, to) do
    Membrane.Logger.debug("""
    Failed to establish link between #{inspect(from.child)} via #{inspect(from.pad_ref)} and
    #{inspect(to.child)} via #{inspect(to.pad_ref)} because #{inspect(name)} does not have
    pad #{inspect(pad_ref)}
    """)
  end
end
