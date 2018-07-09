defmodule Membrane.Core.Element.BufferController do
  @moduledoc """
  Implementation of some functionalities common for all `Membrane.Core.Element`s.

  Key features:
  * handling actions with events, messages, split requests and playback changes
  * handling incoming events, caps and messages, element initializations, playback changes and executing element's callbacks
  * linking and unlinking pads
  """

  alias Membrane.{Core, Element}
  alias Core.{CallbackHandler, PullBuffer}
  alias Element.Context
  alias Core.Element.{ActionHandler, OwnDemandHandler, PadModel, State}
  require PadModel
  use Core.Element.Log
  use Membrane.Helper

  def handle_buffer(pad_name, buffers, state) do
    PadModel.assert_data!(pad_name, %{direction: :sink}, state)

    case PadModel.get_data!(pad_name, :mode, state) do
      :pull -> handle_buffer_pull(pad_name, buffers, state)
      :push -> exec_buffer_handler(pad_name, nil, buffers, state)
    end
  end

  def exec_buffer_handler(pad_name, source, buffers, %State{type: :filter} = state) do
    context = %Context.Process{
      caps: PadModel.get_data!(pad_name, :caps, state),
      source: source,
      source_caps:
        case source do
          {:source, src_name} -> PadModel.get_data!(src_name, :caps, state)
          _ -> nil
        end
    }

    CallbackHandler.exec_and_handle_callback(
      :handle_process,
      ActionHandler,
      [pad_name, buffers, context],
      state
    )
    |> or_warn_error("Error while handling process")
  end

  def exec_buffer_handler(pad_name, _source, buffers, %State{type: :sink} = state) do
    context = %Context.Write{
      caps: PadModel.get_data!(pad_name, :caps, state)
    }

    CallbackHandler.exec_and_handle_callback(
      :handle_write,
      ActionHandler,
      [pad_name, buffers, context],
      state
    )
    |> or_warn_error("Error while handling write")
  end

  defp handle_buffer_pull(pad_name, buffers, state) do
    PadModel.assert_data!(pad_name, %{direction: :sink}, state)

    {{:ok, was_empty?}, state} =
      PadModel.get_and_update_data(
        pad_name,
        :buffer,
        fn pb ->
          was_empty? = pb |> PullBuffer.empty?()

          pb
          |> PullBuffer.store(buffers)
          ~>> ({:ok, pb} -> {{:ok, was_empty?}, pb})
        end,
        state
      )

    if was_empty? do
      OwnDemandHandler.check_and_handle_demands(pad_name, state)
    else
      {:ok, state}
    end
  end
end
