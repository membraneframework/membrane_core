defmodule Membrane.Element.Common do

  use Membrane.Mixins.Log
  alias Membrane.Element.State
  alias Membrane.Helper

  defmacro __using__(_) do
    quote do
      def handle_actions(actions, callback, state) do
        actions |> Helper.Enum.reduce_with(state, fn action, state ->
            handle_action action, callback, state
          end)
      end

      def handle_message(message, state) do
        alias Membrane.Element.Common
        Common.exec_and_handle_callback(:handle_other, [message], state)
          |> Common.orWarnError("Error while handling message")
      end
    end
  end

  def handle_demand(pad_name, size, state) do
    {total_size, state} = state |> State.get_update_pad_data!(:source, pad_name, :demand, fn demand -> {demand+size, demand+size} end)
    exec_and_handle_callback(:handle_demand, [pad_name, total_size], state)
      |> orWarnError("""
        Demand arrived from pad #{inspect pad_name}, but error happened while
        handling it.
        """)
  end

  def exec_and_handle_callback(cb, args, %State{module: module, internal_state: internal_state} = state) do
    with \
      {:call, {:ok, {actions, new_internal_state}}} <- {:call, apply(module, cb, args ++ [internal_state]) |> handle_callback_result(cb)},
      {:handle, {:ok, state}} <- {:handle, actions |> module.base_module.handle_actions(cb, %State{state | internal_state: new_internal_state})}
    do {:ok, state}
    else
      {:call, {:error, reason}} -> warnError "Error while executing callback #{inspect cb}", reason
      {:handle, {:error, reason}} -> warnError "Error while handling actions returned by callback #{inspect cb}", reason
    end
  end

  def handle_callback_result(result, cb \\ :"")
  def handle_callback_result({:ok, {actions, new_internal_state}}, _cb)
  when is_list actions
  do {:ok, {actions, new_internal_state}}
  end
  def handle_callback_result({:error, {reason, new_internal_state}}, cb) do
    cb_name = Atom.to_string cb
    warn """
     Elements callback #{inspect cb_name} returned an error, reason:
     #{inspect reason}

     Elements state: #{inspect new_internal_state}

     Stacktrace:
     #{Exception.format_stacktrace System.stacktrace}
    """
    {:ok, {[], new_internal_state}}
  end
  def handle_callback_result(result, cb) do
    cb_name = Atom.to_string cb
    raise """
    Elements' callback replies are expected to be one of:

        {:ok, {actions, state}}
        {:error, {reason, state}}

    where actions is a list that is specific to base type of the element.

    Instead, callback #{inspect cb_name} returned value of #{inspect result}
    which does not match any of the valid return values.

    This is probably a bug in the element, check if its callbacks return values
    are in the right format.
    """
  end

end
