defmodule Membrane.Core.Element.EffectiveFlowController do
  @moduledoc false

  # Module responsible for the mechanism of resolving effective flow control in elements with pads with auto flow control.
  # Effective flow control of the element determines if the element's pads with auto flow control work in :push or in
  # :pull mode. If the element's effective flow control is set to :push, then all of its auto pads work in :push. Analogically,
  # if the element effective flow control is set to :pull, auto pads also work in :pull.

  # If element A is linked via its input auto pads only to the :push output pads, then effective flow control of
  # element A will be set to :push. Otherwise, if element A is linked via its input auto pads to at least one
  # :pull output pad, element A will set itss effective flow control to :pull and will forward this information
  # via its output auto pads.

  # Resolving effective flow control is performed on
  #  - entering playing playback
  #  - adding and removing pad
  #  - receiving information, that neighbour element effective flow control has changed

  # Effective flow control of a single element can switch between :push and :pull many times during the element's lifetime.

  alias Membrane.Core.Element.DemandController.AutoFlowUtils
  alias Membrane.Core.Element.{DemandCounter, State}

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message
  require Membrane.Logger
  require Membrane.Pad, as: Pad

  @type effective_flow_control :: :push | :pull

  @spec get_pad_effective_flow_control(Pad.ref(), State.t()) :: effective_flow_control()
  def get_pad_effective_flow_control(pad_ref, state) do
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

    Map.keys(state.pads_data)
    |> AutoFlowUtils.increase_demand_counter_if_needed(state)
  end
end
