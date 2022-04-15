defmodule Membrane.Core.CallbackHandler do
  @moduledoc false

  # Behaviour for module that delegates its job to the other module via callbacks.
  # It delivers implementation of executing callbacks and results parsing their
  # results.

  use Bunch

  alias Bunch.Type
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

  @callback handle_action(action :: any, callback :: atom, handler_params_t, state_t) ::
              Type.stateful_try_t(state_t)
  @callback handle_actions(actions :: list, callback :: atom, handler_params_t, state_t) ::
              Type.stateful_try_t(state_t)

  defmacro __using__(_args) do
    quote location: :keep do
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      @impl unquote(__MODULE__)
      def handle_actions(actions, callback, handler_params, state)
          when is_list(actions) do
        actions
        |> Bunch.Enum.try_reduce(state, fn action, state ->
          handle_action(action, callback, handler_params, state)
        end)
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
        ) :: Type.stateful_try_t(state_t)
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

  @spec exec_and_handle_splitted_callback(
          callback :: atom,
          original_callback :: atom,
          module,
          handler_params_t,
          args :: list,
          state_t
        ) :: Type.stateful_try_t(state_t)
  def exec_and_handle_splitted_callback(
        callback,
        original_callback,
        handler_module,
        handler_params \\ %{},
        args_list,
        state
      )
      when is_map(handler_params) do
    split_continuation_arbiter =
      handler_params |> Map.get(:split_continuation_arbiter, fn _state -> true end)

    args_list
    |> Bunch.Enum.try_reduce_while(state, fn args, state ->
      if split_continuation_arbiter.(state) do
        callback
        |> exec_callback(args, handler_params, state)
        |> handle_callback_result(original_callback, handler_module, handler_params, state)
        ~>> ({:ok, state} -> {{:ok, :cont}, state})
      else
        {{:ok, :halt}, state}
      end
    end)
  end

  @spec exec_callback(callback :: atom, args :: list, handler_params_t, state_t) ::
          callback_return_t | any
  defp exec_callback(:handle_init, args, _handler_params, %{module: module}) do
    module
    |> apply(:handle_init, args)
    |> parse_callback_result(module, :handle_init)
  end

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
          {{:ok, actions :: Keyword.t()}, internal_state :: any},
          callback :: atom,
          module,
          handler_params_t,
          state_t
        ) :: Type.stateful_try_t(state_t)
  defp handle_callback_result(cb_result, callback, handler_module, handler_params, state) do
    {result, new_internal_state} = cb_result
    state = Map.put(state, :internal_state, new_internal_state)

    with {{:ok, actions}, state} <- {result, state} do
      exec_handle_actions(actions, callback, handler_module, handler_params, state)
    end
  end

  @spec exec_handle_actions(list, callback :: atom, module, handler_params_t, state_t) ::
          Type.stateful_try_t(state_t)
  defp exec_handle_actions(actions, callback, handler_module, handler_params, state) do
    with {:ok, state} <- handler_module.handle_actions(actions, callback, handler_params, state) do
      {:ok, state}
    else
      {{:error, reason}, state} ->
        Membrane.Logger.error("""
        Error while handling actions returned by callback #{inspect(callback)}
        """)

        {{:error, {:error_handling_actions, reason}}, state}
    end
  end

  @spec parse_callback_result(callback_return_t | any, module, callback :: atom) ::
          Type.stateful_try_t(list, internal_state_t)
  defp parse_callback_result({:ok, new_internal_state}, module, cb),
    do: parse_callback_result({{:ok, []}, new_internal_state}, module, cb)

  defp parse_callback_result({{:ok, actions}, new_internal_state}, _module, _cb) do
    {{:ok, actions}, new_internal_state}
  end

  defp parse_callback_result({:error, reason}, module, :handle_init) do
    raise CallbackError, kind: :error, callback: {module, :handle_init}, reason: reason
  end

  defp parse_callback_result({{:error, reason}, new_internal_state}, module, cb) do
    Membrane.Logger.error("""
    Callback #{inspect(cb)} from module #{inspect(module)} returned an error
    Internal state: #{inspect(new_internal_state, pretty: true)}
    """)

    {{:error, reason}, new_internal_state}
  end

  defp parse_callback_result(result, module, cb) do
    raise CallbackError, kind: :bad_return, callback: {module, cb}, val: result
  end
end
