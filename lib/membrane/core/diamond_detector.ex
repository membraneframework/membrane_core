# defmodule Membrane.Core.DiamondDetector do
#   use GenServer

#   require Membrane.Core.Message, as: Message
#   require Membrane.Core.Utils, as: Utils

#   @timer_interval 100

#   defmodule State do
#     use Bunch.Access

#     defstruct output_pads: %{},
#               input_pads: %{},
#               elements_effective_flow_control: %{},
#               updated_since_last_run?: false,
#               timer_ref: nil
#   end

#   @impl GenServer
#   def init(_arg) do
#     Utils.log_on_error do
#       {:ok, %State{}}
#     end
#   end

#   @impl GenServer
#   def handle_info(Message.new(:effective_flow_control_change, {efc, pid}), %State{} = state) do
#     Utils.log_on_error do
#       state = set_effective_flow_control(pid, efc, state)
#       {:noreply, state}
#     end
#   end

#   @impl GenServer
#   def handle_info(Message.new(:new_element, pid), %State{} = state) do
#     Utils.log_on_error do
#       Process.monitor(pid)
#       state = set_effective_flow_control(pid, :push, state)
#       {:noreply, state}
#     end
#   end

#   @impl GenServer
#   def handle_info(Message.new(:new_link, {from, _from_flow_control, to, to_flow_control}), %State{} = state) do
#     Utils.log_on_error do
#       # if :push not in [from_flow_control, to_flow_control]
#       state =
#         %{state | updated_since_last_run?: true}
#         |> Map.update!(:output_pads, &add_new_output_pad(&1, from, to, to_flow_control))
#         |> Map.update!(:input_pads, &add_new_input_pad(&1, from, to, to_flow_control))
#         |> ensure_timer_running()

#       {:noreply, state}
#     end
#   end

#   @impl GenServer
#   def handle_info(Message.new(:delete_link, {from, to, to_flow_control}), %State{} = state) do
#     state
#     |> Map.update!(:output_pads, )

#   end

#   @impl GenServer
#   def handle_info(:do_algorithm, %State{} = state) do
#     Utils.log_on_error do
#       # do_algorithm
#       {:noreply, %{state | timer_ref: nil, updated_since_last_run?: false}}
#     end
#   end

#   defp set_effective_flow_control(pid, efc, %State{} = state) do
#     %{state | updated_since_last_run?: true}
#     |> Map.update!(:elements_effective_flow_control, &Map.put(&1, pid, efc))
#     |> ensure_timer_running()
#   end

#   defp ensure_timer_running(%State{timer_ref: nil} = state) do
#     timer_ref = self() |> Process.send_after(:do_algorithm, @timer_interval)
#     %{state | timer_ref: timer_ref}
#   end

#   defp ensure_timer_running(state), do: state

#   defp add_new_output_pad(output_pads, from, to, to_flow_control) do
#     entry = {to, to_flow_control}

#     output_pads
#     |> Map.update(from, [entry], &[entry | &1])
#   end

#   defp add_new_input_pad(input_pads, from, to, to_flow_control) do
#     entry = {from, to_flow_control}

#     input_pads
#     |> Map.update(to, [entry], &1[entry | &1])
#   end

# end
