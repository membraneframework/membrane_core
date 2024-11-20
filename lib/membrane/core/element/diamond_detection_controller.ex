defmodule Membrane.Core.Element.DiamondDetectionController do
  @moduledoc false

  require Membrane.Core.Message, as: Message
  require Membrane.Pad, as: Pad

  alias Membrane.Child
  alias Membrane.Core.Element.State
  alias Membrane.Element.PadData

  @type diamond_detection_path :: [{pid(), Child.name(), Pad.ref()}]

  @spec start_diamond_detection(State.t()) :: :ok
  def start_diamond_detection(state) do
    make_ref()
    |> forward_diamond_detection([], state)
  end

  @spec continue_diamond_detection(reference(), diamond_detection_path(), State.t()) :: State.t()
  def continue_diamond_detection(diamond_detection_ref, diamond_detecton_path, state) do
    cond do
      not is_map_key(state.diamond_detection_ref_to_path, diamond_detection_ref) ->
        delete_message = Message.new(:delete_diamond_detection_ref, diamond_detection_ref)
        send_after_time = Membrane.Time.seconds(10) |> Membrane.Time.as_milliseconds(:round)
        self() |> Process.send_after(delete_message, send_after_time)

        :ok = forward_diamond_detection(diamond_detection_ref, diamond_detecton_path, state)

        state
        |> put_in(
          [:diamond_detection_ref_to_path, diamond_detection_ref],
          diamond_detecton_path
        )

      has_cycle?(diamond_detecton_path) ->
        state

      true ->
        # todo: log diamond
        state
    end
  end

  @spec delete_diamond_detection_ref(reference(), State.t()) :: State.t()
  def delete_diamond_detection_ref(diamond_detection_ref, state) do
    state
    |> Map.update!(
      :diamond_detection_ref_to_path,
      &Map.delete(&1, diamond_detection_ref)
    )
  end

  @spec forward_diamond_detection(reference(), diamond_detection_path(), State.t()) :: :ok
  defp forward_diamond_detection(diamond_detection_ref, diamond_detection_path, state) do
    auto_pull_mode? = state.effective_flow_control == :pull

    state.pads_data
    |> Enum.each(fn {pad_ref, pad_data} ->
      if is_output_pull_pad(pad_data, auto_pull_mode?) do
        diamond_detection_path = [{self(), state.name, pad_ref} | diamond_detection_path]

        Message.send(
          pad_data.pid,
          :diamond_detection,
          [diamond_detection_ref, diamond_detection_path]
        )
      end
    end)
  end

  defp is_output_pull_pad(%PadData{} = pad_data, auto_pull_mode?) do
    pad_data.direction == :output and
      (pad_data.flow_control == :manual or
         (pad_data.flow_control == :auto and auto_pull_mode?))
  end

  defp has_cycle?(diamond_detection_path) do
    uniq_length = diamond_detection_path |> Enum.uniq() |> length()
    uniq_length < length(diamond_detection_path)
  end
end
