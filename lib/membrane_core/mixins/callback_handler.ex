defmodule Membrane.Mixins.CallbackHandler do
  use Membrane.Mixins.Log, tags: :core

  @callback handle_action(any, atom, any, any) :: {:ok, any} | {:error, any}
  @callback handle_invalid_action(any, atom, any, [String.t], atom, any) :: {:ok, any} | {:error, any}
  @callback callback_handler_warn_error(String.t, any, any) :: {:error, any}
  @optional_callbacks callback_handler_warn_error: 3


  defmacro __using__(_args) do
    quote location: :keep do
      alias Membrane.Mixins.CallbackHandler
      @allowed_result_atoms [:ok, :async]
      @behaviour CallbackHandler

      def callback_handler_warn_error(message, reason, _state) do
        use Membrane.Mixins.Log
        warn_error message, reason
      end

      def handle_actions(actions, callback, handler_params, state) do
        actions |> Membrane.Helper.Enum.reduce_with(state, fn action, state ->
            handle_action action, callback, handler_params, state
          end)
      end

      def handle_action(action, callback, params, state), do:
        handle_invalid_action(action, callback, params, [], __MODULE__, state)

      def handle_invalid_action(action, callback, _params, available_actions, module, state) do
        callback_handler_warn_error """
          #{module} #{inspect callback} callback results are expected to be one of:
          #{available_actions
              |> List.flatten
              |> Enum.map(fn a -> "\t#{a}" end)
              |> Enum.join("\n")
            }
          but got
          #{inspect action}
          Check if all callbacks return appropriate values.
          """,
          {:invalid_action, action: action, callback: callback, module: module},
          state
      end

      def exec_and_handle_callback(callback, handler_params \\ nil, args, state) do
        internal_state = state |> Map.get(:internal_state)
        module = state |> Map.get(:module)
        with \
          {{result_atom, actions}, new_internal_state} when result_atom in @allowed_result_atoms <- module
            |> apply(callback, args ++ [internal_state])
            |> handle_callback_result(module, callback, state),
          state = state |> Map.put(:internal_state, new_internal_state),
          {:ok, state} <- actions
            |> exec_handle_actions(callback, handler_params, state)
        do
          {result_atom, state}
        else
          {{:error, reason}, new_internal_state} ->
            state = state |> Map.put(:internal_state, new_internal_state)
            {{:error, reason}, state}
          {:error, reason} ->
            {{:error, reason}, state}
        end
      end

      defp exec_handle_actions(actions, callback, handler_params, state) do
        with {:ok, state} <- actions |> handle_actions(callback, handler_params, state)
        do {:ok, state}
        else {:error, reason} ->
          callback_handler_warn_error """
            Error while handling actions returned by callback #{inspect callback}
            """, {:error_handling_actions, reason}, state
        end
      end

      def handle_callback_result({result_atom, new_internal_state}, module, cb, state)
        when result_atom in @allowed_result_atoms do
        handle_callback_result({{result_atom, []}, new_internal_state}, module, cb, state)
      end
      def handle_callback_result({{result_atom, actions}, new_internal_state}, _module, _cb, _state)
        when is_list actions \
        and result_atom in @allowed_result_atoms
        do
          {{result_atom, actions}, new_internal_state}
      end
      def handle_callback_result({{:error, reason}, new_internal_state}, module, cb, state) do
        #TODO: send error to pipeline or do something
        callback_handler_warn_error """
             Callback #{inspect cb} from module #{inspect module} returned an error
             Internal state: #{inspect new_internal_state}
            """, reason, state
        {{:error, reason}, new_internal_state}
      end
      def handle_callback_result(result, module, cb, state) do
        callback_handler_warn_error """
        Callback replies are expected to be one of:

            {:ok, state}
            {{:ok, actions}, state}
            {{:error, reason}, state}

        where actions is a list that is specific to #{inspect module}

        Instead, callback #{inspect cb} from module #{inspect module} returned
        value of #{inspect result} which does not match any of the valid return
        values.

        Check if all callbacks return values are in the right format.
        """,
        {:invalid_callback_result, result: result, module: module, callback: cb},
        state
      end

      defoverridable [
        callback_handler_warn_error: 3,
        handle_actions: 4,
        handle_action: 4,
        handle_invalid_action: 6,
        exec_and_handle_callback: 4,
        handle_callback_result: 4,
      ]

    end
  end

end
