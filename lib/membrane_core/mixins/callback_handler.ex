defmodule Membrane.Mixins.CallbackHandler do
  use Membrane.Mixins.Log, tags: :core

  @type callback_return_t(action_t, internal_state_t) ::
    {{:ok, internal_state_t}} |
    {{:ok, [action_t]}, internal_state_t} |
    {{:error, any}, internal_state_t}

  @callback handle_action(any, atom, any, any) :: {:ok, any} | {:error, any}
  @callback callback_handler_warn_error(String.t, any, any) :: {:error, any}
  @optional_callbacks callback_handler_warn_error: 3

  defmacro __using__(_args) do
    use Membrane.Helper
    quote location: :keep do
      alias Membrane.Mixins.CallbackHandler
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

      def handle_action(action, callback, _params, state), do:
        {{:error, {:invalid_action, action: action, callback: callback, module: state |> Map.get(:module)}}, state}

      def exec_and_handle_callback(callback, handler_params \\ %{}, args, state)
      when is_map(handler_params)
      do
        result = callback |> exec_callback(args, state)
        result |> handle_callback(callback, handler_params, state)
      end

      defp exec_callback(callback, args, state) do
        internal_state = state |> Map.get(:internal_state)
        module = state |> Map.get(:module)
        module |> apply(callback, args ++ [internal_state])
      end

      def exec_and_handle_splitted_callback(
        callback, original_callback, handler_params \\ %{}, args_list, state
      ) when is_map(handler_params)
      do
        split_cont_f = handler_params[:split_cont_f] || fn _ -> true end
        args_list |> Helper.Enum.reduce_while_with(state, fn args, state ->
            if split_cont_f.(state) do
              result = callback |> exec_callback(args |> Helper.listify, state)
              result
                |> handle_callback(original_callback, handler_params, state)
                ~>> ({:ok, state} -> {:ok, {:cont, state}})
            else
              {:ok, {:halt, state}}
            end
          end)
      end

      defp handle_callback(result, callback, handler_params, state) do
        module = state |> Map.get(:module)
        {result, new_internal_state} = result
          |> handle_callback_result(module, callback, state)
        state = state |> Map.put(:internal_state, new_internal_state)
        with \
          {{:ok, actions}, state} <- {result, state},
          {:ok, state} <- actions
            |> exec_handle_actions(callback, handler_params, state)
        do
          {:ok, state}
        end
      end

      defp exec_handle_actions(actions, callback, handler_params, state) do
        with {:ok, state} <- actions |> handle_actions(callback, handler_params, state)
        do {:ok, state}
        else {{:error, reason}, state} ->
          callback_handler_warn_error """
            Error while handling actions returned by callback #{inspect callback}
            """, {:error_handling_actions, reason}, state
        end
      end

      def handle_callback_result({:ok, new_internal_state}, module, cb, state), do:
        handle_callback_result({{:ok, []}, new_internal_state}, module, cb, state)
      def handle_callback_result({{:ok, actions}, new_internal_state}, _module, _cb, _state)
      when is_list actions
      do {{:ok, actions}, new_internal_state}
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
        exec_and_handle_callback: 4,
        handle_callback_result: 4,
      ]

    end
  end

end
