defmodule Membrane.Core.Bin.PadController do
  @moduledoc false

  # Module handling linking and unlinking pads.

  use Bunch
  alias Bunch.Type
  alias Membrane.{Core, LinkError, Pad}
  alias Membrane.Core.{CallbackHandler, Child, Message}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Bin.{ActionHandler, State}
  alias Membrane.Core.Parent.{ChildLifeController, Link, LinkParser}
  alias Membrane.Bin.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Bin.CallbackContext.{PadAdded, PadRemoved}
  require Membrane.Logger
  require Membrane.Pad

  @doc """
  Handles a link request from the bin's parent.
  """
  @spec handle_external_link_request(
          Pad.ref_t(),
          Pad.direction_t(),
          ChildLifeController.LinkHandler.link_id_t(),
          Membrane.ParentSpec.pad_options_t(),
          State.t()
        ) :: State.t() | no_return
  def handle_external_link_request(pad_ref, direction, link_id, pad_options, state) do
    Membrane.Logger.debug("Received link request on pad #{inspect(pad_ref)}")
    pad_name = Pad.name_by_ref(pad_ref)

    info =
      case Map.fetch(state.pads.info, pad_name) do
        {:ok, info} ->
          info

        :error ->
          raise LinkError,
                "Tried to link via unknown pad #{inspect(pad_name)} of #{inspect(state.name)}"
      end

    :ok = Child.PadController.validate_pad_being_linked!(pad_ref, direction, info, state)
    pad_options = Child.PadController.parse_pad_options!(pad_name, pad_options, state)

    state =
      case PadModel.get_data(state, pad_ref) do
        {:error, {:unknown_pad, pad_ref}} ->
          init_pad_data(pad_ref, info, state)

        # This case is for pads that were instantiated before the external link request,
        # that is in the internal link request (see `handle_internal_link_request/4`).
        # This is possible only for static pads. It might have happened that we already
        # received a link response for such a pad, so we should reply immediately.
        {:ok, data} ->
          if data.response_received? do
            Membrane.Logger.debug("Sending link response, #{inspect(pad_ref)}")
            Message.send(state.parent_pid, :link_response, link_id)
          end

          state
      end

    state = PadModel.update_data!(state, pad_ref, &%{&1 | link_id: link_id, options: pad_options})
    {:ok, state} = maybe_handle_pad_added(pad_ref, state)
    state
  end

  @doc """
  Handles a link request coming from the bin itself when linking a bin's pad
  to a pad of one of its children.
  """
  @spec handle_internal_link_request(
          Pad.ref_t(),
          Link.Endpoint.t(),
          ChildLifeController.spec_ref_t(),
          State.t()
        ) :: State.t()
  def handle_internal_link_request(pad_ref, child_endpoint, spec_ref, state) do
    pad_name = Pad.name_by_ref(pad_ref)
    info = Map.fetch!(state.pads.info, pad_name)

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

    PadModel.update_data!(
      state,
      pad_ref,
      &%{&1 | endpoint: child_endpoint, spec_ref: spec_ref}
    )
  end

  @doc """
  Sends link response to the parent for each of bin's pads involved in given spec.
  """
  @spec respond_links(ChildLifeController.spec_ref_t(), State.t()) :: State.t()
  def respond_links(spec_ref, state) do
    state.pads.data
    |> Map.values()
    |> Enum.filter(&(&1.spec_ref == spec_ref))
    |> Enum.reduce(state, fn pad_data, state ->
      if pad_data.link_id do
        Message.send(state.parent_pid, :link_response, pad_data.link_id)
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
  @spec all_pads_linked?(ChildLifeController.spec_ref_t(), State.t()) :: boolean()
  def all_pads_linked?(spec_ref, state) do
    state.pads.data
    |> Map.values()
    |> Enum.filter(&(&1.spec_ref == spec_ref))
    |> Enum.all?(& &1.linked?)
  end

  @doc """
  Verifies linked pad and proxies the message to the proper child.
  """
  @spec handle_link(
          Pad.direction_t(),
          LinkParser.raw_endpoint_t(),
          LinkParser.raw_endpoint_t(),
          %{initiator: :parent}
          | %{initiator: :sibling, other_info: PadModel.pad_info_t() | nil, link_metadata: map},
          Core.Bin.State.t()
        ) :: Type.stateful_try_t(PadModel.pad_info_t(), Core.Bin.State.t())
  def handle_link(direction, endpoint, other_endpoint, params, state) do
    pad_data = PadModel.get_data!(state, endpoint.pad_ref)
    %{spec_ref: spec_ref, endpoint: child_endpoint} = pad_data

    pad_props =
      Map.merge(endpoint.pad_props, child_endpoint.pad_props, fn key,
                                                                 external_value,
                                                                 internal_value ->
        if key in [
             :target_queue_size,
             :min_demand_factor,
             :auto_demand_size,
             :toilet_capacity
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

    reply =
      Message.call!(child_endpoint.pid, :handle_link, [
        direction,
        child_endpoint,
        other_endpoint,
        params
      ])

    state = PadModel.set_data!(state, endpoint.pad_ref, :linked?, true)
    state = PadModel.set_data!(state, endpoint.pad_ref, :endpoint, child_endpoint)
    state = ChildLifeController.LinkHandler.proceed_spec_linking(spec_ref, state)
    {reply, state}
  end

  @doc """
  Handles situation where the pad has been unlinked (e.g. when connected element has been removed from the pipeline)
  """
  @spec handle_unlink(Pad.ref_t(), Core.Bin.State.t()) :: Type.stateful_try_t(Core.Bin.State.t())
  def handle_unlink(pad_ref, state) do
    with {:ok, state} <- maybe_handle_pad_removed(pad_ref, state) do
      PadModel.delete_data(state, pad_ref)
    end
  end

  @spec maybe_handle_pad_added(Pad.ref_t(), Core.Bin.State.t()) ::
          Type.stateful_try_t(Core.Bin.State.t())
  defp maybe_handle_pad_added(ref, state) do
    %{options: pad_opts, direction: direction, availability: availability} =
      PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      context = &CallbackContext.PadAdded.from_state(&1, options: pad_opts, direction: direction)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_added,
        ActionHandler,
        %{context: context},
        [ref],
        state
      )
    else
      {:ok, state}
    end
  end

  @spec maybe_handle_pad_removed(Pad.ref_t(), Core.Bin.State.t()) ::
          Type.stateful_try_t(Core.Bin.State.t())
  defp maybe_handle_pad_removed(ref, state) do
    %{direction: direction, availability: availability} = PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      context = &CallbackContext.PadRemoved.from_state(&1, direction: direction)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_removed,
        ActionHandler,
        %{context: context},
        [ref],
        state
      )
    else
      {:ok, state}
    end
  end

  defp init_pad_data(pad_ref, info, state) do
    data =
      Map.merge(info, %{
        ref: pad_ref,
        link_id: nil,
        endpoint: nil,
        linked?: false,
        response_received?: false,
        spec_ref: nil,
        options: nil
      })

    data = struct!(Membrane.Bin.PadData, data)

    put_in(state, [:pads, :data, pad_ref], data)
  end
end
