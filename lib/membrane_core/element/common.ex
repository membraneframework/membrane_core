defmodule Membrane.Element.Common do
  alias Membrane.Element.State
  alias Membrane.Helper

  defmacro __using__(_) do
    quote do
      defdelegate handle_message(message, state), to: Membrane.Element.Common
      defdelegate handle_actions(actions, callback, state), to: Membrane.Element.Common
    end
  end

  def handle_demand(pad_name, size, %State{module: module, internal_state: internal_state} = state) do
    {total_size, state} = state |> State.get_update_pad_data!(:source, pad_name, :demand, fn demand -> {demand+size, demand+size} end)
    {:ok, {actions, new_internal_state}} = wrap_internal_return(module.handle_demand(pad_name, total_size, internal_state))
    handle_actions actions, :handle_demand, %State{state | internal_state: new_internal_state}
  end

  def handle_actions(actions, callback, %State{module: module} = state) do
    actions |> Helper.Enum.reduce_with(state, fn action, state ->
        module.base_module.handle_action action, callback, state
      end)
  end

  def handle_message(message, %State{module: module, internal_state: internal_state} = state) do
    with \
      {:ok, {actions, new_internal_state}} <- wrap_internal_return(module.handle_other(message, internal_state)),
      {:ok, state} <- handle_actions(actions, :handle_other, %State{state | internal_state: new_internal_state})
    do
      {:ok, state}
    end
  end

  # defp handle_invalid_callback_return(return) do
  #   raise """
  #   Elements' callback replies are expected to be one of:
  #
  #       {:ok, {actions, state}}
  #       {:error, {reason, state}}
  #
  #   where actions is a list that is specific to base type of the element.
  #
  #   But got return value of #{inspect(return)} which does not match any of the
  #   valid return values.
  #
  #   This is probably a bug in the element, check if its callbacks return values
  #   in the right format.
  #   """
  # end


  # Helper function that allows to distinguish potentially failed calls in with
  # clauses that operate on internal element state from others that operate on
  # global element state.
  def wrap_internal_return({:ok, info}), do: {:ok, info}
  def wrap_internal_return({:error, reason}), do: {:internal, {:error, reason}}

end
