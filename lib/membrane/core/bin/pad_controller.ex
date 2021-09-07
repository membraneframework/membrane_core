defmodule Membrane.Core.Bin.PadController do
  @moduledoc false

  # Module handling linking and unlinking pads.

  use Bunch
  alias Bunch.Type
  alias Membrane.{Core, Pad}
  alias Membrane.Core.{CallbackHandler, Child, Message}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Bin.ActionHandler
  alias Membrane.Core.Parent.{ChildLifeController, LinkParser}
  alias Membrane.Bin.CallbackContext

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Bin.CallbackContext.{PadAdded, PadRemoved}
  require Membrane.Logger
  require Membrane.Pad

  def handle_link_request(pad_ref, direction, link_id, pad_props, state) do
    Membrane.Logger.debug("Received link request on pad #{inspect(pad_ref)}")
    pad_name = Pad.name_by_ref(pad_ref)
    info = Map.fetch!(state.pads.info, pad_name)

    :ok = Child.PadController.validate_pad_being_linked!(pad_ref, direction, info, state)
    pad_props = Child.PadController.parse_pad_props!(pad_props, pad_name, state)

    if info.availability == :always do
      if PadModel.get_data!(state, pad_ref, :link_id) == :ready do
        Membrane.Logger.debug("Sending link response, #{inspect(pad_ref)}")
        Message.send(state.watcher, :link_response, link_id)
      end

      PadModel.set_data!(state, pad_ref, :link_id, link_id)
    else
      data =
        Map.merge(info, %{
          link_id: link_id,
          endpoint: nil,
          linked?: false,
          spec_ref: nil,
          options: pad_props.options
        })

      state = put_in(state, [:pads, :data, pad_ref], data)
      {:ok, state} = handle_pad_added(pad_ref, state)
      state
    end
  end

  @doc """
  Verifies linked pad, initializes it's data.
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
    :ok = Child.PadController.validate_pad_mode!(pad_data, other_info)

    reply =
      Message.call(endpoint.pid, :handle_link, [
        direction,
        endpoint,
        other,
        other_info,
        link_metadata
      ])

    state = PadModel.set_data!(state, this.pad_ref, :linked?, true)

    state =
      if state.pads.data
         |> Map.values()
         |> Enum.filter(&(&1.spec_ref == spec_ref))
         |> Enum.all?(& &1.linked?) do
        Membrane.Logger.debug("Spec playback init #{inspect(spec_ref)}")
        ChildLifeController.StartupHandler.init_playback_state(spec_ref, state)
      else
        state
      end

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
    %{options: pad_opts, direction: direction} = PadModel.get_data!(state, ref)
    context = &CallbackContext.PadAdded.from_state(&1, options: pad_opts, direction: direction)

    CallbackHandler.exec_and_handle_callback(
      :handle_pad_added,
      ActionHandler,
      %{context: context},
      [ref],
      state
    )
  end

  @spec handle_pad_removed(Pad.ref_t(), Core.Bin.State.t()) ::
          Type.stateful_try_t(Core.Bin.State.t())
  def handle_pad_removed(ref, state) do
    %{direction: direction, availability: availability} = PadModel.get_data!(state, ref)
    context = &CallbackContext.PadRemoved.from_state(&1, direction: direction)

    if Pad.availability_mode(availability) == :dynamic do
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
end
