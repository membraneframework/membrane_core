defmodule Membrane.Core.Element.StreamFormatController do
  @moduledoc false

  # Module handling stream format received on input pads.

  use Bunch

  alias Membrane.{Pad, StreamFormat}
  alias Membrane.Core.{CallbackHandler, Telemetry}
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    ActionHandler,
    AutoFlowController,
    CallbackContext,
    PlaybackQueue,
    State
  }

  alias Membrane.Core.Element.ManualFlowController.InputQueue

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
      Telemetry.report_stream_format(stream_format, inspect(pad_ref))

      queue = data.input_queue

      cond do
        # stream format goes to the manual flow control input queue
        queue && not InputQueue.empty?(queue) ->
          PadModel.set_data!(
            state,
            pad_ref,
            :input_queue,
            InputQueue.store(queue, :stream_format, stream_format)
          )

        # stream format goes to the auto flow control queue
        pad_ref in state.awaiting_auto_input_pads ->
          AutoFlowController.store_stream_format_in_queue(pad_ref, stream_format, state)

        true ->
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
      stream_format_validation_params: validation_params,
      name: pad_name,
      stream_format: old_stream_format
    } = PadModel.get_data!(state, pad_ref)

    validation_params = [{state.module, pad_name} | validation_params]
    :ok = validate_stream_format!(:input, validation_params, stream_format)

    context = &CallbackContext.from_state(&1, old_stream_format: old_stream_format)

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
          StreamFormat.t()
        ) :: :ok
  def validate_stream_format!(direction, params, stream_format) do
    unless is_struct(stream_format) do
      raise Membrane.StreamFormatError, """
      Stream format must be defined as a struct, therefore it cannot be: #{inspect(stream_format)}
      """
    end

    for {module, pad_name} <- params do
      unless module.membrane_stream_format_match?(pad_name, stream_format) do
        pretty_accepted_format =
          module.membrane_pads()
          |> get_in([pad_name, :accepted_formats_str])
          |> case do
            [pattern_string] ->
              "`#{pattern_string}`"

            many_patterns ->
              [last | head] = Enum.reverse(many_patterns)
              head = head |> Enum.reverse() |> Enum.map_join(", ", &"`#{&1}`")
              "#{head} or `#{last}`"
          end

        raise Membrane.StreamFormatError, """
        Stream format: #{inspect(stream_format)} is not matching accepted format pattern \
        #{pretty_accepted_format} in def_#{direction}_pad for pad #{inspect(pad_name)} \
        in #{inspect(module)}. Beware that stream format is forwarded by the default implemetation \
        of handle_stream_format in filters.
        """
      end
    end

    :ok
  end
end
