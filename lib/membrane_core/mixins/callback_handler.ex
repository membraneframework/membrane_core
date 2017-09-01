defmodule Membrane.Mixins.CallbackHandler do
  use Membrane.Mixins.Log, tags: :core

  @callback handle_action(any, atom, any, any) :: {:ok, any} | {:error, any}
  @callback handle_invalid_action(any, atom, any, [String.t], atom, any) :: {:ok, any} | {:error, any}

  defmacro __using__(_args) do
    quote location: :keep do
      alias Membrane.Mixins.CallbackHandler
      @behaviour CallbackHandler

      def handle_actions(actions, callback, handler_params, state) do
        actions |> Membrane.Helper.Enum.reduce_with(state, fn action, state ->
            handle_action action, callback, handler_params, state
          end)
      end

      def handle_action(action, callback, params, state), do:
        handle_invalid_action(action, callback, params, [], __MODULE__, state)

      def handle_invalid_action(action, callback, _params, available_actions, module, _state) do
        warn_error """
          #{module} #{inspect callback} callback results are expected to be one of:
          #{available_actions
              |> List.flatten
              |> Enum.map(fn a -> "\t#{a}" end)
              |> Enum.join("\n")
            }
          but got
          #{inspect action}
          Check if all callbacks return appropriate values.
          """, {:invalid_action, action: action, callback: callback, module: module}
      end

      def exec_and_handle_callback(callback, handler_params \\ nil, args, state) do
        internal_state = state |> Map.get(:internal_state)
        module = state |> Map.get(:module)
        with \
          {{:ok, actions}, new_internal_state} <- module
            |> apply(callback, args ++ [internal_state])
            |> handle_callback_result(module, callback),
          state = state |> Map.put(:internal_state, new_internal_state),
          {:ok, state} <- actions
            |> exec_handle_actions(callback, handler_params, state)
        do
          {:ok, state}
        end
      end

      defp exec_handle_actions(actions, callback, handler_params, state) do
        with {:ok, state} <- actions |> handle_actions(callback, handler_params, state)
        do {:ok, state}
        else {:error, reason} ->
          warn_error """
            Error while handling actions returned by callback #{inspect callback}
            """, {:error_handling_actions, reason}
        end
      end

      def handle_callback_result({:ok, new_internal_state}, module, cb), do:
        handle_callback_result({{:ok, []}, new_internal_state}, module, cb)
      def handle_callback_result({{:ok, actions}, new_internal_state}, _module, _cb)
      when is_list actions
      do {{:ok, actions}, new_internal_state}
      end
      def handle_callback_result({{:error, reason}, new_internal_state}, module, cb) do
        #TODO: send error to pipeline or do something
        warn_error """
             Callback #{inspect cb} from module #{inspect module} returned an error
             Internal state: #{inspect new_internal_state}
            """, reason
        {{:ok, []}, new_internal_state}
      end
      def handle_callback_result(result, module, cb) do
        warn_error """
        Callback replies are expected to be one of:

            {:ok, state}
            {{:ok, actions}, state}
            {{:error, reason}, state}

        where actions is a list that is specific to base type of the element.

        Instead, callback #{inspect cb} from module #{inspect module} returned
        value of #{inspect result} which does not match any of the valid return
        values.

        Check if all callbacks return values are in the right format.
        """, {:invalid_callback_result, result: result, module: module, callback: cb}
      end

      defoverridable [
        handle_actions: 4,
        handle_action: 4,
        handle_invalid_action: 6,
        exec_and_handle_callback: 4,
        handle_callback_result: 3,
      ]

    end
  end

end
