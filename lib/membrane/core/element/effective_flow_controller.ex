defmodule Membrane.Core.Element.EffectiveFlowController do
  @moduledoc false

  # Module responsible for the mechanism of resolving effective flow control in elements with pads with auto flow control.
  # Effective flow control of the element determines if the element's pads with auto flow control work in :push or in
  # :pull mode. If the element's effective flow control is set to :push, then all of its auto pads work in :push. Analogically,
  # if the element effective flow control is set to :pull, auto pads also work in :pull.

  # If element A is linked via its input auto pads only to the :push output pads of other elements, then effective flow
  # control of element A will be set to :push. Otherwise, if element A is linked via its input auto pads to at least one
  # :pull output pad, element A will set its effective flow control to :pull and will forward this information
  # via its output auto pads.

  # Resolving effective flow control is performed on
  #  - entering playing playback
  #  - adding and removing pad
  #  - receiving information, that neighbour element effective flow control has changed

  # Effective flow control of a single element can switch between :push and :pull many times during the element's lifetime.

  alias Membrane.Core.Element.DemandController
  alias Membrane.Core.Element.DemandController.AutoFlowUtils
  alias Membrane.Core.Element.{AtomicDemand, State}

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

  @spec handle_sender_effective_flow_control(
          Pad.ref(),
          effective_flow_control(),
          State.t()
        ) ::
          State.t()
  def handle_sender_effective_flow_control(input_pad_ref, other_effective_flow_control, state) do
    pad_data = PadModel.get_data!(state, input_pad_ref)
    pad_data = %{pad_data | other_effective_flow_control: other_effective_flow_control}
    state = PadModel.set_data!(state, input_pad_ref, pad_data)

    cond do
      state.playback != :playing or pad_data.direction != :input or pad_data.flow_control != :auto ->
        state

      other_effective_flow_control == state.effective_flow_control ->
        :ok =
          PadModel.get_data!(state, input_pad_ref, :atomic_demand)
          |> AtomicDemand.set_receiver_status({:resolved, state.effective_flow_control})

        state

      other_effective_flow_control == :pull ->
        set_effective_flow_control(:pull, input_pad_ref, state)

      other_effective_flow_control == :push ->
        resolve_effective_flow_control(input_pad_ref, state)
    end
  end

  @spec resolve_effective_flow_control(Pad.ref(), State.t()) :: State.t()
  def resolve_effective_flow_control(triggering_pad \\ nil, state) do
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

    set_effective_flow_control(new_effective_flow_control, triggering_pad, state)
  end

  defp set_effective_flow_control(
         effective_flow_control,
         _triggering_pad,
         %{effective_flow_control: effective_flow_control} = state
       ),
       do: state

  defp set_effective_flow_control(new_effective_flow_control, triggering_pad, state) do
    Membrane.Logger.debug(
      "Transiting `flow_control: :auto` pads to #{inspect(new_effective_flow_control)} effective flow control"
    )

    state = %{state | effective_flow_control: new_effective_flow_control}

    state.pads_data
    |> Enum.filter(fn {_ref, %{flow_control: flow_control}} -> flow_control == :auto end)
    |> Enum.each(fn
      {_ref, %{direction: :output} = pad_data} ->
        :ok =
          AtomicDemand.set_sender_status(
            pad_data.atomic_demand,
            {:resolved, new_effective_flow_control}
          )

        :ok = AtomicDemand.set_receiver_status(pad_data.atomic_demand, :to_be_resolved)

        Message.send(
          pad_data.pid,
          :sender_effective_flow_control_resolved,
          [pad_data.other_ref, new_effective_flow_control]
        )

      {pad_ref, %{direction: :input} = pad_data} ->
        if triggering_pad in [pad_ref, nil] or
             AtomicDemand.get_receiver_status(pad_data.atomic_demand) != :to_be_resolved do
          :ok =
            AtomicDemand.set_receiver_status(
              pad_data.atomic_demand,
              {:resolved, new_effective_flow_control}
            )
        end
    end)

    with %{effective_flow_control: :pull} <- state do
      Enum.reduce(state.pads_data, state, fn
        {pad_ref, %{direction: :output, flow_control: :auto, end_of_stream?: false}}, state ->
          DemandController.snapshot_atomic_demand(pad_ref, state)

        _pad_entry, state ->
          state
      end)
    end
    |> AutoFlowUtils.pop_queues_and_bump_demand()
  end
end
