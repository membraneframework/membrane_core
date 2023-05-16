defmodule Membrane.Core.CallbackHandler do
  @moduledoc false

  # Behaviour for module that delegates its job to the other module via callbacks.
  # It delivers implementation of executing callbacks and results parsing their
  # results.

  use Bunch

  alias Membrane.CallbackError

  require Membrane.Logger

  @type state :: %{
          :module => module,
          :internal_state => internal_state,
          optional(atom) => any
        }

  @type internal_state :: any

  @type callback_return(action, internal_state) ::
          {[action], internal_state}

  @type callback_return :: callback_return(any, any)

  @type handler_params :: map

  @callback handle_action(action :: any, callback :: atom, handler_params, state) :: state
  @callback transform_actions(actions :: list, callback :: atom, handler_params, state) ::
              {actions :: list, state}

  defmacro __using__(_args) do
    quote location: :keep do
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      @impl unquote(__MODULE__)
      def transform_actions(actions, _callback, _handler_params, state) do
        {actions, state}
      end

      defoverridable unquote(__MODULE__)
    end
  end

  @spec exec_and_handle_callback(
          callback :: atom,
          module,
          handler_params,
          args :: list,
          state
        ) :: state
  def exec_and_handle_callback(
        callback,
        handler_module,
        handler_params,
        args,
        state
      )
      when is_map(handler_params) do
    result = exec_callback(callback, args, handler_params, state)
    handle_callback_result(result, callback, handler_module, handler_params, state)
  end

  @spec exec_and_handle_split_callback(
          callback :: atom,
          original_callback :: atom,
          module,
          handler_params,
          args_list :: list,
          state
        ) :: state
  def exec_and_handle_split_callback(
        callback,
        original_callback,
        handler_module,
        handler_params,
        args_list,
        state
      )

  def exec_and_handle_split_callback(
        callback,
        original_callback,
        handler_module,
        %{split_continuation_arbiter: split_continuation_arbiter} = handler_params,
        args_list,
        state
      ) do
    Enum.reduce_while(args_list, state, fn args, state ->
      if split_continuation_arbiter.(state) do
        state =
          callback
          |> exec_callback(args, handler_params, state)
          |> handle_callback_result(original_callback, handler_module, handler_params, state)

        {:cont, state}
      else
        {:halt, state}
      end
    end)
  end

  def exec_and_handle_split_callback(
        callback,
        original_callback,
        handler_module,
        %{} = handler_params,
        args_list,
        state
      ) do
    Enum.reduce(args_list, state, fn args, state ->
      callback
      |> exec_callback(args, handler_params, state)
      |> handle_callback_result(original_callback, handler_module, handler_params, state)
    end)
  end

  @spec exec_callback(callback :: atom, args :: list, handler_params, state) ::
          {list, internal_state}
  defp exec_callback(
         callback,
         args,
         %{context: context_fun},
         %{module: module, internal_state: internal_state} = state
       ) do
    args = args ++ [context_fun.(state), internal_state]

    callback_result =
      try do
        apply(module, callback, args)
      rescue
        e in UndefinedFunctionError ->
          with %{module: ^module, function: ^callback, arity: arity} <- e do
            reraise CallbackError,
                    [kind: :not_implemented, callback: {module, callback}, arity: arity],
                    __STACKTRACE__
          end

          reraise e, __STACKTRACE__
      end

    case callback_result do
      {actions, _state} when is_list(actions) ->
        callback_result

      _result ->
        raise CallbackError,
          kind: :bad_return,
          callback: {module, callback},
          value: callback_result
    end
  end

  @spec handle_callback_result(
          {actions :: Keyword.t(), internal_state},
          callback :: atom,
          module,
          handler_params,
          state
        ) :: state
  defp handle_callback_result(cb_result, callback, handler_module, handler_params, state) do
    {actions, new_internal_state} = cb_result
    state = %{state | internal_state: new_internal_state}

    {actions, state} =
      try do
        handler_module.transform_actions(actions, callback, handler_params, state)
      rescue
        e ->
          Membrane.Logger.error("""
          Error handling actions returned by callback #{inspect(state.module)}.#{callback}
          """)

          reraise e, __STACKTRACE__
      end

    Enum.reduce(actions, state, fn action, state ->
      try do
        handler_module.handle_action(action, callback, handler_params, state)
      rescue
        e ->
          Membrane.Logger.error("""
          Error handling action #{inspect(action)} returned by callback #{inspect(state.module)}.#{callback}
          """)

          reraise e, __STACKTRACE__
      end
    end)
  end
end
