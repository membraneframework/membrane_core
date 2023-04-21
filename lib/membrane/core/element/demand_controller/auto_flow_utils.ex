defmodule Membrane.Core.Element.DemandController.AutoFlowUtils do
  @moduledoc false

  alias Membrane.Core.Element.{
    DemandCounter,
    State
  }

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Pad, as: Pad

  @lacking_buffer_size_lowerbound 200
  @lacking_buffer_size_upperbound 400

  defguardp is_input_auto_pad_data(pad_data)
            when is_map(pad_data) and is_map_key(pad_data, :flow_control) and
                   pad_data.flow_control == :auto and is_map_key(pad_data, :direction) and
                   pad_data.direction == :input

  @spec increase_demand_counter_if_needed(Pad.ref() | [Pad.ref()], State.t()) :: State.t()
  def increase_demand_counter_if_needed(pad_ref_list, state) when is_list(pad_ref_list) do
    Enum.reduce(pad_ref_list, state, fn pad_ref, state ->
      case PadModel.get_data(state, pad_ref) do
        {:ok, pad_data} when is_input_auto_pad_data(pad_data) ->
          do_increase_demand_counter_if_needed(pad_data, state)

        _other ->
          state
      end
    end)
  end

  def increase_demand_counter_if_needed(pad_ref, state) when Pad.is_pad_ref(pad_ref) do
    with {:ok, pad_data} when is_input_auto_pad_data(pad_data) <-
           PadModel.get_data(state, pad_ref) do
      do_increase_demand_counter_if_needed(pad_data, state)
    else
      _other -> state
    end
  end

  defp do_increase_demand_counter_if_needed(pad_data, state) do
    if increase_demand_counter?(pad_data, state) do
      diff = @lacking_buffer_size_upperbound - pad_data.lacking_buffer_size
      :ok = DemandCounter.increase(pad_data.demand_counter, diff)

      PadModel.set_data!(
        state,
        pad_data.ref,
        :lacking_buffer_size,
        @lacking_buffer_size_upperbound
      )
    else
      state
    end
  end

  defp increase_demand_counter?(pad_data, state) do
    %{
      flow_control: flow_control,
      lacking_buffer_size: lacking_buffer_size,
      associated_pads: associated_pads
    } = pad_data

    flow_control == :auto and
      state.effective_flow_control == :pull and
      lacking_buffer_size < @lacking_buffer_size_lowerbound and
      Enum.all?(associated_pads, &demand_counter_positive?(&1, state))
  end

  defp demand_counter_positive?(pad_ref, state) do
    demand_counter_value =
      PadModel.get_data!(state, pad_ref, :demand_counter)
      |> DemandCounter.get()

    demand_counter_value > 0
  end
end
