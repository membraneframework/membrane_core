defmodule Membrane.Element.Common do

  use Membrane.Mixins.Log
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
    {:ok, {actions, new_internal_state}} = module.handle_demand(pad_name, total_size, internal_state) |> handle_callback_result
    handle_actions actions, :handle_demand, %State{state | internal_state: new_internal_state}
  end

  def handle_actions(actions, callback, %State{module: module} = state) do
    actions |> Helper.Enum.reduce_with(state, fn action, state ->
        module.base_module.handle_action action, callback, state
      end)
  end

  def handle_message(message, %State{module: module, internal_state: internal_state} = state) do
    with \
      {:ok, {actions, new_internal_state}} <- module.handle_other(message, internal_state) |> handle_callback_result,
      {:ok, state} <- handle_actions(actions, :handle_other, %State{state | internal_state: new_internal_state})
    do
      {:ok, state}
    else
      {:error, reason} -> handle_error reason, "handle message"
    end
  end

  def handle_error(reason, activity) do
    warn """
      Cannot #{inspect activity}, reason: #{inspect reason}
    """
    {:error, reason}
  end

  def handle_callback_result({:ok, {actions, new_internal_state}})
  when is_list actions
  do {:ok, {actions, new_internal_state}}
  end
  def handle_callback_result({:error, {reason, new_internal_state}}) do
    warn """
     Elements callback returned an error, reason: #{inspect reason}.

     Elements state: #{inspect new_internal_state}

     Stacktrace:
     #{Exception.format_stacktrace System.stacktrace}
    """
    {:ok, {[], new_internal_state}}
  end
  def handle_callback_result(result) do
    raise """
    Elements' callback replies are expected to be one of:

        {:ok, {actions, state}}
        {:error, {reason, state}}

    where actions is a list that is specific to base type of the element.

    But got return value of #{inspect result} which does not match any of the
    valid return values.

    This is probably a bug in the element, check if its callbacks return values
    are in the right format.
    """
  end

end
