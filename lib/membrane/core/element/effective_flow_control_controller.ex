defmodule Membrane.Core.Element.EffectiveFlowControlController do
  @moduledoc false

  alias Membrane.Core.Element.State

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message
  require Membrane.Pad, as: Pad

  @spec pad_effective_flow_control(Pad.ref(), State.t()) :: Pad.effective_flow_control()
  def pad_effective_flow_control(pad_ref, state) do
    pad_name = Pad.name_by_ref(pad_ref)

    state.pads_info
    |> get_in([pad_name, :flow_control])
    |> case do
      :manual -> :pull
      :push -> :push
      :auto -> state.effective_flow_control
    end
  end

  @spec handle_input_pad_added(Pad.ref(), State.t()) :: State.t()
  def handle_input_pad_added(pad_ref, state) do
    with %{pads_data: %{^pad_ref => %{flow_control: :auto} = pad_data}} <- state do
      handle_other_effective_flow_control(
        pad_ref,
        pad_data.other_effective_flow_control,
        state
      )
    end
  end

  @spec handle_other_effective_flow_control(Pad.ref(), Pad.effective_flow_control(), State.t()) ::
          State.t()
  def handle_other_effective_flow_control(my_pad_ref, other_effective_flow_control, state) do
    pad_data = PadModel.get_data!(state, my_pad_ref)

    if pad_data.direction != :input do
      raise "this function should be called only for input pads"
    end

    pad_data = %{pad_data | other_effective_flow_control: other_effective_flow_control}
    state = PadModel.set_data!(state, my_pad_ref, pad_data)

    cond do
      pad_data.flow_control != :auto or other_effective_flow_control == :undefined or
          state.playback == :stopped ->
        state

      state.effective_flow_control == :undefined ->
        resolve_effective_flow_control(state)

      state.effective_flow_control == :push and other_effective_flow_control == :pull ->
        raise "dupa dupa 123"

      state.effective_flow_control == :pull or other_effective_flow_control == :push ->
        state
    end
  end

  @spec resolve_effective_flow_control(State.t()) :: State.t()
  def resolve_effective_flow_control(state) do
    input_auto_pads =
      Map.values(state.pads_data)
      |> Enum.filter(&(&1.direction == :input && &1.flow_control == :auto))

    effective_flow_control =
      input_auto_pads
      |> Enum.group_by(& &1.other_effective_flow_control)
      |> case do
        %{pull: _pads} -> :pull
        %{push: _pads} -> :push
        %{} -> :undefined
      end

    if effective_flow_control != :undefined do
      Enum.each(state.pads_data, fn {_pad_ref, pad_data} ->
        with %{direction: :output, flow_control: :auto} <- pad_data do
          Message.send(pad_data.pid, :other_effective_flow_control, [
            pad_data.other_ref,
            effective_flow_control
          ])
        end
      end)
    end

    %{state | effective_flow_control: effective_flow_control}
  end
end
