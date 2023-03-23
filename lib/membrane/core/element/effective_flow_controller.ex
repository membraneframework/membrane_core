defmodule Membrane.Core.Element.EffectiveFlowController do
  @moduledoc false

  alias Membrane.Core.Element.{
    DemandController,
    DemandCounter,
    State
  }

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message
  require Membrane.Logger
  require Membrane.Pad, as: Pad

  @type effective_flow_control :: :push | :pull

  @spec pad_effective_flow_control(Pad.ref(), State.t()) :: effective_flow_control()
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
    with %{pads_data: %{^pad_ref => %{flow_control: :auto, direction: :input} = pad_data}} <-
           state do
      handle_other_effective_flow_control(
        pad_ref,
        pad_data.other_effective_flow_control,
        state
      )
    end
  end

  @spec handle_other_effective_flow_control(
          Pad.ref(),
          effective_flow_control(),
          State.t()
        ) ::
          State.t()
  def handle_other_effective_flow_control(my_pad_ref, other_effective_flow_control, state) do
    pad_data = PadModel.get_data!(state, my_pad_ref)
    pad_data = %{pad_data | other_effective_flow_control: other_effective_flow_control}
    state = PadModel.set_data!(state, my_pad_ref, pad_data)

    cond do
      state.playback != :playing or pad_data.direction != :input or pad_data.flow_control != :auto ->
        state

      other_effective_flow_control == state.effective_flow_control ->
        :ok =
          PadModel.get_data!(state, my_pad_ref, :demand_counter)
          |> DemandCounter.set_receiver_mode(state.effective_flow_control)

        state

      other_effective_flow_control == :pull ->
        set_effective_flow_control(:pull, state)

      other_effective_flow_control == :push ->
        resolve_effective_flow_control(state)
    end
  end

  @spec resolve_effective_flow_control(State.t()) :: State.t()
  def resolve_effective_flow_control(state) do
    senders_flow_modes =
      Map.values(state.pads_data)
      |> Enum.filter(&(&1.direction == :input && &1.flow_control == :auto))
      |> Enum.map(& &1.other_effective_flow_control)

    new_effective_flow_control =
      cond do
        Enum.member?(senders_flow_modes, :pull) -> :pull
        Enum.member?(senders_flow_modes, :push) -> :push
        true -> state.effective_flow_control
      end

    set_effective_flow_control(new_effective_flow_control, state)
  end

  defp set_effective_flow_control(
         effective_flow_control,
         %{effective_flow_control: effective_flow_control} = state
       ),
       do: state

  defp set_effective_flow_control(new_effective_flow_control, state) do
    Membrane.Logger.debug(
      "Transiting `flow_control: :auto` pads to #{inspect(new_effective_flow_control)} effective flow control"
    )

    state = %{state | effective_flow_control: new_effective_flow_control}

    Enum.each(state.pads_data, fn
      {_ref, %{flow_control: :auto, direction: :output} = pad_data} ->
        :ok = DemandCounter.set_sender_mode(pad_data.demand_counter, new_effective_flow_control)
        :ok = DemandCounter.set_receiver_mode(pad_data.demand_counter, :to_be_resolved)

        Message.send(pad_data.pid, :other_effective_flow_control_resolved, [
          pad_data.other_ref,
          new_effective_flow_control
        ])

      {_ref, %{flow_control: :auto, direction: :input, demand_counter: demand_counter}} ->
        :ok = DemandCounter.set_receiver_mode(demand_counter, new_effective_flow_control)

      _pad_entry ->
        :ok
    end)

    Enum.reduce(state.pads_data, state, fn
      {pad_ref, %{flow_control: :auto, direction: :input}}, state ->
        # DemandController.send_auto_demand_if_needed(pad_ref, state)
        DemandController.increase_demand_counter_if_needed(pad_ref, state)

      _pad_entry, state ->
        state
    end)
  end

  # defp update_demand_counter_receiver_mode(pad_ref, state) do
  #   PadModel.get_data!(state, pad_ref, [:demand_counter])
  #   |> DemandCounter.set_receiver_mode(state.effective_flow_control)
  # end
end
