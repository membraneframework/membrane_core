defmodule Membrane.Core.CallbackHandler do
  @moduledoc false

  # Behaviour for module that delegates its job to the other module via callbacks.
  # It delivers implementation of executing callbacks and results parsing their
  # results.

  use Bunch

  alias Membrane.CallbackError

  require Membrane.Logger

  @type state_t :: %{
          :module => module,
          :internal_state => internal_state_t,
          optional(atom) => any
        }

  @type internal_state_t :: any

  @type callback_return_t(action, internal_state) ::
          {:ok, internal_state}
          | {{:ok, [action]}, internal_state}
          | {{:error, any}, internal_state}
          | {:error, any}

  @type callback_return_t :: callback_return_t(any, any)

  @type handler_params_t :: map

  @callback handle_action(action :: any, callback :: atom, handler_params_t, state_t) :: state_t
  @callback transform_actions(actions :: list, callback :: atom, handler_params_t, state_t) ::
              {actions :: list, state_t}

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
          handler_params_t,
          args :: list,
          state_t
        ) :: state_t
  def exec_and_handle_callback(
        callback,
        handler_module,
        handler_params \\ %{},
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
          handler_params_t,
          args_list :: list,
          state_t
        ) :: state_t
  def exec_and_handle_split_callback(
        callback,
        original_callback,
        handler_module,
        handler_params \\ %{},
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

  @spec exec_callback(callback :: atom, args :: list, handler_params_t, state_t) ::
          {list, internal_state_t}
  defp exec_callback(
         callback,
         args,
         %{context: context_fun},
         %{module: module, internal_state: internal_state} = state
       ) do
    args = args ++ [context_fun.(state), internal_state]

    module
    |> apply(callback, args)
    |> parse_callback_result(module, callback)
  end

  defp exec_callback(
         callback,
         args,
         _handler_params,
         %{module: module, internal_state: internal_state}
       ) do
    args = args ++ [internal_state]

    module
    |> apply(callback, args)
    |> parse_callback_result(module, callback)
  end

  @spec handle_callback_result(
          {actions :: Keyword.t(), internal_state_t},
          callback :: atom,
          module,
          handler_params_t,
          state_t
        ) :: state_t
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

  @spec parse_callback_result(callback_return_t | any, module, callback :: atom) ::
          {list, internal_state_t}
  defp parse_callback_result({:ok, new_internal_state}, _module, _cb) do
    {[], new_internal_state}
  end

  defp parse_callback_result({{:ok, actions}, new_internal_state}, _module, _cb) do
    {actions, new_internal_state}
  end

  defp parse_callback_result({:error, reason}, module, :handle_init) do
    raise CallbackError, kind: :error, callback: {module, :handle_init}, reason: reason
  end

  defp parse_callback_result({{:error, reason}, new_internal_state}, module, cb) do
    raise CallbackError,
      kind: :error,
      callback: {module, cb},
      reason: reason,
      state: new_internal_state
  end

  defp parse_callback_result(result, module, cb) do
    raise CallbackError, kind: :bad_return, callback: {module, cb}, val: result
  end
end
