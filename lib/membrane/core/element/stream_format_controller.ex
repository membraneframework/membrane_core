defmodule Membrane.Core.Element.StreamFormatController do
  @moduledoc false

  # Module handling stream format received on input pads.

  use Bunch

  alias Membrane.{Pad, StreamFormat}
  alias Membrane.Core.{CallbackHandler, Telemetry}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.{ActionHandler, CallbackContext, InputQueue, PlaybackQueue, State}

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Telemetry

  @type stream_format_validation_param() :: {module(), Pad.name()}
  @type stream_format_validation_params() :: [stream_format_validation_param()]

  @doc """
  Handles incoming stream format: either stores it in InputQueue, or executes element callback.
  """
  @spec handle_stream_format(Pad.ref(), StreamFormat.t(), State.t()) :: State.t()
  def handle_stream_format(pad_ref, stream_format, state) do
    withl pad: {:ok, data} <- PadModel.get_data(state, pad_ref),
          playback: %State{playback: :playing} <- state do
      %{direction: :input} = data
      Telemetry.report_metric(:stream_format, 1, inspect(pad_ref))

      queue = data.input_queue

      if queue && not InputQueue.empty?(queue) do
        PadModel.set_data!(
          state,
          pad_ref,
          :input_queue,
          InputQueue.store(queue, :stream_format, stream_format)
        )
      else
        exec_handle_stream_format(pad_ref, stream_format, state)
      end
    else
      pad: {:error, :unknown_pad} ->
        # We've got stream format from already unlinked pad
        state

      playback: _playback ->
        PlaybackQueue.store(&handle_stream_format(pad_ref, stream_format, &1), state)
    end
  end

  @spec exec_handle_stream_format(Pad.ref(), StreamFormat.t(), params :: map, State.t()) ::
          State.t()
  def exec_handle_stream_format(pad_ref, stream_format, params \\ %{}, state) do
    %{
      stream_format_validation_params: stream_format_validation_params,
      name: pad_name,
      stream_format: old_stream_format
    } = PadModel.get_data!(state, pad_ref)

    context = &CallbackContext.from_state(&1, old_stream_format: old_stream_format)

    :ok =
      validate_stream_format!(
        :input,
        [{state.module, pad_name} | stream_format_validation_params],
        stream_format,
        state
      )

    state =
      CallbackHandler.exec_and_handle_callback(
        :handle_stream_format,
        ActionHandler,
        %{context: context} |> Map.merge(params),
        [pad_ref, stream_format],
        state
      )

    PadModel.set_data!(state, pad_ref, :stream_format, stream_format)
  end

  @spec validate_stream_format!(
          Pad.direction(),
          stream_format_validation_params(),
          StreamFormat.t(),
          State.t()
        ) :: :ok
  def validate_stream_format!(direction, params, stream_format, state) do
    unless is_struct(stream_format) do
      raise Membrane.StreamFormatError, """
      Stream format must be defined as a struct, therefore it cannot be: #{inspect(stream_format)}
      """
    end

    for {module, pad_name} <- params do
      unless module.membrane_stream_format_match?(pad_name, stream_format) do
        pattern_string = get_in(state, [:pads_info, pad_name, :accepted_formats_str])

        raise Membrane.StreamFormatError, """
        Stream format: #{inspect(stream_format)} is not matching accepted format pattern "#{pattern_string}" in def_#{direction}_pad
        for pad #{inspect(pad_name)} in #{inspect(module)}
        """
      end
    end

    :ok
  end
end
