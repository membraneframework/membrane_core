defmodule Membrane.Core.Element.DemandController.AutoFlowUtils do
  @moduledoc false

  alias Membrane.Core.Element.{
    DemandCounter,
    State
  }

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Pad, as: Pad

  defguardp is_input_auto_pad_data(pad_data)
            when is_map(pad_data) and is_map_key(pad_data, :flow_control) and
                   pad_data.flow_control == :auto and is_map_key(pad_data, :direction) and
                   pad_data.direction == :input

  @spec auto_adjust_demand_counter(Pad.ref() | [Pad.ref()], State.t()) :: State.t()
  def auto_adjust_demand_counter(pad_ref_list, state) when is_list(pad_ref_list) do
    Enum.reduce(pad_ref_list, state, &auto_adjust_demand_counter/2)
  end

  def auto_adjust_demand_counter(pad_ref, state) when Pad.is_pad_ref(pad_ref) do
    PadModel.get_data!(state, pad_ref)
    |> do_auto_adjust_demand_counter(state)
  end

  defp do_auto_adjust_demand_counter(pad_data, state) when is_input_auto_pad_data(pad_data) do
    if increase_demand_counter?(pad_data, state) do
      diff = pad_data.auto_demand_size - pad_data.lacking_buffer_size
      :ok = DemandCounter.increase(pad_data.demand_counter, diff)

      PadModel.set_data!(
        state,
        pad_data.ref,
        :lacking_buffer_size,
        pad_data.auto_demand_size
      )
    else
      state
    end
  end

  defp do_auto_adjust_demand_counter(%{ref: ref}, _state) do
    raise "#{__MODULE__}.auto_adjust_demand_counter/2 can be called only for auto input pads, while #{inspect(ref)} is not such a pad."
  end

  defp increase_demand_counter?(pad_data, state) do
    state.effective_flow_control == :pull and
      pad_data.lacking_buffer_size < pad_data.auto_demand_size / 2 and
      Enum.all?(pad_data.associated_pads, &demand_counter_positive?(&1, state))
  end

  defp demand_counter_positive?(pad_ref, state) do
    demand_counter_value =
      PadModel.get_data!(state, pad_ref, :demand_counter)
      |> DemandCounter.get()

    demand_counter_value > 0
  end
end
