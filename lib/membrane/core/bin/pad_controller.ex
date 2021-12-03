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
  Handles link request from outside of the bin.
  """
  @spec handle_external_link_request(
          Pad.ref_t(),
          Pad.direction_t(),
          ChildLifeController.LinkHandler.link_id_t(),
          Membrane.ParentSpec.pad_props_t(),
          State.t()
        ) :: State.t()
  def handle_external_link_request(pad_ref, direction, link_id, pad_props, state) do
    Membrane.Logger.debug("Received link request on pad #{inspect(pad_ref)}")
    pad_name = Pad.name_by_ref(pad_ref)
    info = Map.fetch!(state.pads.info, pad_name)

    :ok = Child.PadController.validate_pad_being_linked!(pad_ref, direction, info, state)
    pad_props = Child.PadController.parse_pad_props!(pad_props, pad_name, state)

    state =
      with {:ok, response_received?} <- PadModel.get_data(state, pad_ref, :response_received?) do
        if response_received? do
          Membrane.Logger.debug("Sending link response, #{inspect(pad_ref)}")
          Message.send(state.parent_pid, :link_response, link_id)
        end

        state
      else
        {:error, {:unknown_pad, pad_ref}} ->
          init_pad_data(pad_ref, info, state)
      end

    {spec_ref, state} =
      PadModel.get_and_update_data!(
        state,
        pad_ref,
        &{&1.spec_ref, %{&1 | link_id: link_id, options: pad_props.options}}
      )

    state =
      if spec_ref do
        ChildLifeController.LinkHandler.proceed_spec_linking(spec_ref, state)
      else
        state
      end

    {:ok, state} = handle_pad_added(pad_ref, state)
    state
  end

  @doc """
  Handles link request from one of bin's children.
  """
  @spec handle_internal_link_request(
          Pad.ref_t(),
          Link.Endpoint.t(),
          ChildLifeController.spec_ref_t(),
          State.t()
        ) :: State.t()
  def handle_internal_link_request(pad_ref, endpoint, spec_ref, state) do
    pad_name = Pad.name_by_ref(pad_ref)
    info = Map.fetch!(state.pads.info, pad_name)

    state =
      cond do
        :ok == PadModel.assert_instance(state, pad_ref) ->
          state

        info.availability == :always ->
          init_pad_data(pad_ref, info, state)

        true ->
          raise LinkError, "Dynamic pads must be firstly linked externally, then internally"
      end

    PadModel.update_data!(state, pad_ref, &%{&1 | endpoint: endpoint, spec_ref: spec_ref})
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
          PadModel.pad_info_t() | nil,
          map,
          Core.Bin.State.t()
        ) :: Type.stateful_try_t(PadModel.pad_info_t(), Core.Bin.State.t())
  def handle_link(direction, this, other, other_info, link_metadata, state) do
    pad_data = PadModel.get_data!(state, this.pad_ref)
    %{spec_ref: spec_ref, endpoint: endpoint} = pad_data

    :ok =
      Child.PadController.validate_pad_mode!(
        {this.pad_ref, pad_data},
        {other.pad_ref, other_info}
      )

    reply =
      Message.call(endpoint.pid, :handle_link, [
        direction,
        endpoint,
        other,
        other_info,
        link_metadata
      ])

    state = PadModel.set_data!(state, this.pad_ref, :linked?, true)
    state = ChildLifeController.LinkHandler.proceed_spec_linking(spec_ref, state)
    {reply, state}
  end

  @doc """
  Handles situation where pad has been unlinked (e.g. when connected element has been removed from pipline)
  """
  @spec handle_unlink(Pad.ref_t(), Core.Bin.State.t()) :: Type.stateful_try_t(Core.Bin.State.t())
  def handle_unlink(pad_ref, state) do
    with {:ok, state} <- handle_pad_removed(pad_ref, state),
         {:ok, state} <- PadModel.delete_data(state, pad_ref) do
      {:ok, state}
    end
  end

  @spec handle_pad_added(Pad.ref_t(), Core.Bin.State.t()) ::
          Type.stateful_try_t(Core.Bin.State.t())
  defp handle_pad_added(ref, state) do
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

  @spec handle_pad_removed(Pad.ref_t(), Core.Bin.State.t()) ::
          Type.stateful_try_t(Core.Bin.State.t())
  defp handle_pad_removed(ref, state) do
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
