defmodule Membrane.Core.Bin.PadController do
  @moduledoc false

  # Module handling linking and unlinking pads.

  use Bunch

  alias Membrane.{Core, LinkError, Pad}
  alias Membrane.Core.Bin.{ActionHandler, CallbackContext, State}
  alias Membrane.Core.{CallbackHandler, Child, Message}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.StreamFormatController
  alias Membrane.Core.Parent.{ChildLifeController, Link, SpecificationParser}

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Logger
  require Membrane.Pad

  @doc """
  Handles a link request from the bin's parent.
  """
  @spec handle_external_link_request(
          Pad.ref(),
          Pad.direction(),
          Link.id(),
          Membrane.ChildrenSpec.pad_options(),
          State.t()
        ) :: State.t() | no_return
  def handle_external_link_request(pad_ref, direction, link_id, pad_options, state) do
    Membrane.Logger.debug(
      "Got external link request, link id: #{inspect(link_id)}, pad ref: #{inspect(pad_ref)}"
    )

    pad_name = Pad.name_by_ref(pad_ref)

    info =
      case Map.fetch(state.pads_info, pad_name) do
        {:ok, info} ->
          info

        :error ->
          raise LinkError,
                "Tried to link via unknown pad #{inspect(pad_name)} of #{inspect(state.name)}"
      end

    :ok = Child.PadController.validate_pad_being_linked!(direction, info)
    pad_options = Child.PadController.parse_pad_options!(pad_name, pad_options, state)

    state =
      case PadModel.get_data(state, pad_ref) do
        {:error, :unknown_pad} ->
          init_pad_data(pad_ref, info, state)

        # This case is for pads that were instantiated before the external link request,
        # that is in the internal link request (see `handle_internal_link_request/4`).
        # This is possible only for static pads. It might have happened that we already
        # received a link response for such a pad, so we should reply immediately.
        {:ok, data} ->
          if data.response_received? do
            Membrane.Logger.debug(
              "Sending link response, link_id: #{inspect(link_id)}, pad: #{inspect(pad_ref)}"
            )

            Message.send(state.parent_pid, :link_response, [link_id, direction])
          end

          state
      end

    state = PadModel.update_data!(state, pad_ref, &%{&1 | link_id: link_id, options: pad_options})
    state = maybe_handle_pad_added(pad_ref, state)

    unless PadModel.get_data!(state, pad_ref, :endpoint) do
      # If there's no endpoint associated to the pad, no internal link to the pad
      # has been requested in the bin yet
      Process.send_after(self(), Message.new(:linking_timeout, pad_ref), 5000)
    end

    state
  end

  @spec remove_dynamic_pad!(Pad.ref(), State.t()) :: State.t()
  def remove_dynamic_pad!(pad_ref, state) do
    case pad_ref do
      Pad.ref(_name, _id) ->
        Message.send(state.parent_pid, :child_pad_removed, [state.name, pad_ref])
        PadModel.delete_data!(state, pad_ref)

      name when is_atom(name) and state.terminating? ->
        state

      name when is_atom(name) ->
        raise Membrane.PadError,
              "Tried to unlink bin static pad #{inspect(pad_ref)}. Static pads cannot be unlinked unless bin is terminating"
    end
  end

  @spec handle_linking_timeout(Pad.ref(), State.t()) :: :ok | no_return()
  def handle_linking_timeout(pad_ref, state) do
    case PadModel.get_data(state, pad_ref) do
      {:ok, %{endpoint: nil}} = pad_data ->
        raise Membrane.LinkError,
              "Bin pad #{inspect(pad_ref)} wasn't linked internally within timeout. Pad data: #{inspect(pad_data, pretty: true)}"

      _other ->
        :ok
    end
  end

  @doc """
  Handles a link request coming from the bin itself when linking a bin's pad
  to a pad of one of its children.
  """
  @spec handle_internal_link_request(
          Pad.ref(),
          Link.Endpoint.t(),
          ChildLifeController.spec_ref(),
          State.t()
        ) :: State.t()
  def handle_internal_link_request(pad_ref, child_endpoint, spec_ref, state) do
    Membrane.Logger.debug(
      "Got internal link request, pad ref #{inspect(pad_ref)}, child #{inspect(child_endpoint.child)}, spec #{inspect(spec_ref)}"
    )

    pad_name = Pad.name_by_ref(pad_ref)
    info = Map.fetch!(state.pads_info, pad_name)

    state =
      cond do
        :ok == PadModel.assert_instance(state, pad_ref) ->
          state

        # Static pads can be linked internally before the external link request
        info.availability == :always ->
          init_pad_data(pad_ref, info, state)

        true ->
          raise LinkError, "Dynamic pads must be firstly linked externally, then internally"
      end

    state =
      PadModel.update_data!(
        state,
        pad_ref,
        &%{&1 | endpoint: child_endpoint, spec_ref: spec_ref}
      )

    state
  end

  @doc """
  Sends link response to the parent for each of bin's pads involved in given spec.
  """
  @spec respond_links(ChildLifeController.spec_ref(), State.t()) :: State.t()
  def respond_links(spec_ref, state) do
    state.pads_data
    |> Map.values()
    |> Enum.filter(&(&1.spec_ref == spec_ref))
    |> Enum.reduce(state, fn pad_data, state ->
      if pad_data.link_id do
        Membrane.Logger.debug(
          "Sending link response, link_id: #{inspect(pad_data.link_id)}, pad: #{inspect(pad_data.ref)}"
        )

        Message.send(state.parent_pid, :link_response, [pad_data.link_id, pad_data.direction])
        state
      else
        Membrane.Core.Child.PadModel.set_data!(
          state,
          pad_data.ref,
          :response_received?,
          true
        )
      end
    end)
  end

  @doc """
  Returns true if all pads of given `spec_ref` are linked, false otherwise.
  """
  @spec all_pads_linked?(ChildLifeController.spec_ref(), State.t()) :: boolean()
  def all_pads_linked?(spec_ref, state) do
    state.pads_data
    |> Map.values()
    |> Enum.filter(&(&1.spec_ref == spec_ref))
    |> Enum.all?(& &1.linked?)
  end

  @doc """
  Verifies linked pad and proxies the message to the proper child.
  """
  @spec handle_link(
          Pad.direction(),
          SpecificationParser.raw_endpoint(),
          SpecificationParser.raw_endpoint(),
          %{
            initiator: :parent,
            stream_format_validation_params:
              StreamFormatController.stream_format_validation_params()
          }
          | %{
              initiator: :sibling,
              other_info: PadModel.pad_info() | nil,
              link_metadata: map,
              stream_format_validation_params:
                StreamFormatController.stream_format_validation_params()
            },
          Core.Bin.State.t()
        ) :: {Core.Element.PadController.link_call_reply(), Core.Bin.State.t()}
  def handle_link(direction, endpoint, other_endpoint, params, state) do
    Membrane.Logger.debug("Handle link #{inspect(endpoint, pretty: true)}")

    with {:ok, pad_data} <- PadModel.get_data(state, endpoint.pad_ref) do
      %{spec_ref: spec_ref, endpoint: child_endpoint, name: pad_name} = pad_data

      pad_props =
        Map.merge(endpoint.pad_props, child_endpoint.pad_props, fn key,
                                                                   external_value,
                                                                   internal_value ->
          if key in [
               :target_queue_size,
               :min_demand_factor,
               :auto_demand_size,
               :toilet_capacity,
               :throttling_factor
             ] do
            external_value || internal_value
          else
            internal_value
          end
        end)

      child_endpoint = %{child_endpoint | pad_props: pad_props}

      if params.initiator == :sibling do
        :ok =
          Child.PadController.validate_pad_mode!(
            {endpoint.pad_ref, pad_data},
            {other_endpoint.pad_ref, params.other_info}
          )
      end

      params =
        Map.update!(
          params,
          :stream_format_validation_params,
          &[{state.module, pad_name} | &1]
        )

      reply =
        Message.call!(child_endpoint.pid, :handle_link, [
          direction,
          child_endpoint,
          other_endpoint,
          params
        ])

      state = PadModel.set_data!(state, endpoint.pad_ref, :linked?, true)
      state = PadModel.set_data!(state, endpoint.pad_ref, :endpoint, child_endpoint)
      state = ChildLifeController.proceed_spec_startup(spec_ref, state)
      {reply, state}
    else
      {:error, :unknown_pad} ->
        {{:error, {:unknown_pad, state.name, state.module, endpoint.pad_ref}}, state}
    end
  end

  @doc """
  Handles situation where the pad has been unlinked (e.g. when connected element has been removed from the pipeline)
  """
  @spec handle_unlink(Pad.ref(), Core.Bin.State.t()) :: Core.Bin.State.t()
  def handle_unlink(pad_ref, state) do
    with {:ok, %{availability: :on_request}} <- PadModel.get_data(state, pad_ref) do
      state = maybe_handle_pad_removed(pad_ref, state)
      endpoint = PadModel.get_data!(state, pad_ref, :endpoint)
      {pad_data, state} = PadModel.pop_data!(state, pad_ref)

      if endpoint do
        Message.send(endpoint.pid, :handle_unlink, endpoint.pad_ref)
        ChildLifeController.proceed_spec_startup(pad_data.spec_ref, state)
      else
        Membrane.Logger.debug("""
        Tried to send :handle_unlink to the endpoint while unlinking #{inspect(pad_ref)},
        but the endpoint is neither linked internally nor :handle_link was received yet
        """)

        state
      end
    else
      {:ok, %{availability: :always}} when state.terminating? ->
        state

      {:ok, %{availability: :always}} ->
        raise Membrane.PadError,
              "Tried to unlink a static pad #{inspect(pad_ref)}. Static pads cannot be unlinked unless element is terminating"

      {:error, :unknown_pad} ->
        Membrane.Logger.debug(
          "Ignoring unlinking pad #{inspect(pad_ref)} that hasn't been successfully linked"
        )

        state
    end
  end

  @spec maybe_handle_pad_added(Pad.ref(), Core.Bin.State.t()) :: Core.Bin.State.t()
  defp maybe_handle_pad_added(ref, state) do
    %{options: pad_opts, availability: availability} = PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      context = &CallbackContext.from_state(&1, pad_options: pad_opts)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_added,
        ActionHandler,
        %{context: context},
        [ref],
        state
      )
    else
      state
    end
  end

  @spec maybe_handle_pad_removed(Pad.ref(), Core.Bin.State.t()) :: Core.Bin.State.t()
  defp maybe_handle_pad_removed(ref, state) do
    %{availability: availability} = PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      CallbackHandler.exec_and_handle_callback(
        :handle_pad_removed,
        ActionHandler,
        %{context: &CallbackContext.from_state/1},
        [ref],
        state
      )
    else
      state
    end
  end

  defp init_pad_data(pad_ref, info, state) do
    data =
      Map.delete(info, :accepted_formats_str)
      |> Map.merge(%{
        ref: pad_ref,
        link_id: nil,
        endpoint: nil,
        linked?: false,
        response_received?: false,
        spec_ref: nil,
        options: nil
      })

    data = struct!(Membrane.Bin.PadData, data)

    put_in(state, [:pads_data, pad_ref], data)
  end
end
