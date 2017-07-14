defmodule Membrane.Mixins.CallbackHandler do
  use Membrane.Mixins.Log

  @callback handle_action(any, atom, any, any) :: {:ok, any} | {:error, any}

  defmacro __using__(_args) do
    quote location: :keep do
      alias Membrane.Mixins.CallbackHandler
      @behaviour CallbackHandler

      def handle_actions(actions, callback, handler_params, state) do
        actions |> Membrane.Helper.Enum.reduce_with(state, fn action, state ->
            handle_action action, callback, handler_params, state
          end)
      end

      def handle_action(action, callback, _params, state), do:
        invalid_action(__MODULE__, action, [], callback, state)

      def invalid_action(module, action, available_actions, callback, state) do
        warn_error """
          #{module} #{inspect callback} callback results are expected to be one of:
          #{available_actions |> Enum.map(fn a -> "\t#{a}" end) |> Enum.join("\n")}
          but got
          #{inspect action}
          Check if all callbacks return appropriate values.
          """, :invalid_action
      end

      def exec_and_handle_callback(callback, handler_params \\ nil, args, state) do
        internal_state = state |> Map.get(:internal_state)
        module = state |> Map.get(:module)
        with \
          {:ok, {actions, new_internal_state}} <- apply(module, callback, args ++ [internal_state])
            |> handle_callback_result(callback)
            |> or_warn_error("Error while executing callback #{inspect callback}"),
          state = state |> Map.put(:internal_state, new_internal_state),
          {:ok, state} <- actions
            |> handle_actions(callback, handler_params, state)
            |> or_warn_error("Error while handling actions returned by callback #{inspect callback}")
        do
          {:ok, state}
        end
      end

      def handle_callback_result(result, cb \\ "")
      def handle_callback_result({:ok, {actions, new_internal_state}}, _cb)
      when is_list actions
      do {:ok, {actions, new_internal_state}}
      end
      def handle_callback_result({:error, {reason, new_internal_state}}, cb) do
        warn_error """
             Callback #{inspect cb} returned an error
             Internal state: #{inspect new_internal_state}
            """, reason
        {:ok, {[], new_internal_state}}
      end
      def handle_callback_result(result, cb) do
        raise """
        Callback replies are expected to be one of:

            {:ok, {actions, state}}
            {:error, {reason, state}}

        where actions is a list that is specific to base type of the element.

        Instead, callback #{inspect cb} returned value of #{inspect result}
        which does not match any of the valid return values.

        Check if all callbacks return values are in the right format.
        """
      end

      defoverridable [
        handle_actions: 4,
        handle_action: 4,
        invalid_action: 5,
        exec_and_handle_callback: 4,
        handle_callback_result: 2,
      ]

    end
  end

end
