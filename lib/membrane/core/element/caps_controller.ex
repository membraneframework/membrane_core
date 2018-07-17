defmodule Membrane.Core.Element.CapsController do
  @moduledoc false
  # Module handling caps infoming through sink pads.

  alias Membrane.{Caps, Core, Element}
  alias Core.{CallbackHandler, PullBuffer}
  alias Core.Element.{ActionHandler, PadModel, State}
  alias Element.Pad
  require PadModel
  use Core.Element.Log
  use Membrane.Helper

  @doc """
  Handles incoming caps: either stores them in PullBuffer, or executes element callback.
  """
  @spec handle_caps(Pad.name_t(), Caps.t(), State.t()) :: State.stateful_try_t()
  def handle_caps(pad_name, caps, state) do
    PadModel.assert_data!(pad_name, %{direction: :sink}, state)
    data = PadModel.get_data!(pad_name, state)

    if data.mode == :pull and not (data.buffer |> PullBuffer.empty?()) do
      PadModel.update_data(
        pad_name,
        :buffer,
        &(&1 |> PullBuffer.store(:caps, caps)),
        state
      )
    else
      exec_handle_caps(pad_name, caps, state)
    end
  end

  @spec exec_handle_caps(Pad.name_t(), Caps.t(), State.t()) :: State.stateful_try_t()
  def exec_handle_caps(pad_name, caps, state) do
    %{accepted_caps: accepted_caps, caps: old_caps} = PadModel.get_data!(pad_name, state)

    withl match: true <- Caps.Matcher.match?(accepted_caps, caps),
          callback:
            {:ok, state} <-
              CallbackHandler.exec_and_handle_callback(
                :handle_caps,
                ActionHandler,
                [pad_name, caps],
                [caps: old_caps],
                state
              ) do
      {:ok, PadModel.set_data!(pad_name, :caps, caps, state)}
    else
      match: false ->
        warn_error(
          """
          Received caps: #{inspect(caps)} that are not specified in known_sink_pads
          for pad #{inspect(pad_name)}. Specs of accepted caps are:
          #{inspect(accepted_caps, pretty: true)}
          """,
          :invalid_caps,
          state
        )

      callback: {{:error, reason}, state} ->
        warn_error("Error while handling caps", reason, state)
    end
  end
end
