defmodule Membrane.Core.Element.BufferController do
  @moduledoc false
  # Module handling buffers incoming through sink pads.

  alias Membrane.{Buffer, Core, Element}
  alias Core.{CallbackHandler, PullBuffer}
  alias Element.{CallbackContext, Pad}
  alias Core.Element.{ActionHandler, DemandHandler, PadModel, State}
  require CallbackContext.{Process, Write}
  require PadModel
  use Core.Element.Log
  use Bunch

  @doc """
  Handles incoming buffer: either stores it in PullBuffer, or executes element's
  callback. Also calls `Membrane.Core.Element.DemandHandler.check_and_handle_demands/2`
  to check if there are any unsupplied demands.
  """
  @spec handle_buffer(Pad.name_t(), [Buffer.t()] | Buffer.t(), State.t()) ::
          State.stateful_try_t()
  def handle_buffer(pad_name, buffers, state) do
    PadModel.assert_data!(pad_name, %{direction: :sink}, state)

    case PadModel.get_data!(pad_name, :mode, state) do
      :pull -> handle_buffer_pull(pad_name, buffers, state)
      :push -> exec_buffer_handler(pad_name, nil, buffers, state)
    end
  end

  @doc """
  Executes `handle_process` or `handle_write_list` callback.
  """
  @spec exec_buffer_handler(
          Pad.name_t(),
          {:source, Pad.name_t()} | :self | nil,
          [Buffer.t()] | Buffer.t(),
          State.t()
        ) :: State.stateful_try_t()
  def exec_buffer_handler(pad_name, source, buffers, %State{type: :filter} = state) do
    context =
      CallbackContext.Process.from_state(
        state,
        caps: PadModel.get_data!(pad_name, :caps, state),
        source: source,
        source_caps:
          case source do
            {:source, src_name} -> PadModel.get_data!(src_name, :caps, state)
            _ -> nil
          end
      )

    CallbackHandler.exec_and_handle_callback(
      :handle_process_list,
      ActionHandler,
      [pad_name, buffers, context],
      state
    )
    |> or_warn_error("Error while handling process")
  end

  def exec_buffer_handler(pad_name, _source, buffers, %State{type: :sink} = state) do
    context =
      CallbackContext.Write.from_state(state, caps: PadModel.get_data!(pad_name, :caps, state))

    CallbackHandler.exec_and_handle_callback(
      :handle_write_list,
      ActionHandler,
      [pad_name, buffers, context],
      state
    )
    |> or_warn_error("Error while handling write")
  end

  @spec handle_buffer_pull(Pad.name_t(), [Buffer.t()] | Buffer.t(), State.t()) ::
          State.stateful_try_t()
  defp handle_buffer_pull(pad_name, buffers, state) do
    PadModel.assert_data!(pad_name, %{direction: :sink}, state)

    with {{:ok, was_empty?}, state} <-
           PadModel.get_and_update_data!(
             pad_name,
             :buffer,
             fn pb ->
               was_empty? = pb |> PullBuffer.empty?()

               pb
               |> PullBuffer.store(buffers)
               ~>> ({:ok, pb} -> {{:ok, was_empty?}, pb})
             end,
             state
           ) do
      if was_empty? do
        DemandHandler.check_and_handle_demands(pad_name, state)
      else
        {:ok, state}
      end
    end
  end
end
