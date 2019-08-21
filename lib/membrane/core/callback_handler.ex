defmodule Membrane.Core.CallbackHandler do
  @moduledoc false
  # Behaviour for module that delegates its job to the other module via callbacks.
  # It delivers implementation of executing callbacks and results parsing their
  # results.

  alias Bunch.Type
  alias Membrane.CallbackError
  use Bunch
  use Membrane.Log, tags: :core

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
    result = callback |> exec_callback(args, handler_params, state)
    result |> handle_callback_result(callback, handler_module, handler_params, state)
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
      handler_params |> Map.get(:split_continuation_arbiter, fn _ -> true end)

    args_list
    |> Bunch.Enum.try_reduce_while(state, fn args, state ->
      if split_continuation_arbiter.(state) do
        result = callback |> exec_callback(args |> Bunch.listify(), handler_params, state)

        result
        |> handle_callback_result(original_callback, handler_module, handler_params, state)
        ~>> ({:ok, state} -> {{:ok, :cont}, state})
      else
        {{:ok, :halt}, state}
      end
    end)
  end

  @spec exec_callback(callback :: atom, args :: list, handler_params_t, state_t) ::
          callback_return_t | any
  defp exec_callback(callback, args, handler_params, state) do
    module = state |> Map.fetch!(:module)

    args =
      case handler_params |> Map.fetch(:context) do
        :error -> args
        {:ok, f} -> args ++ [f.(state)]
      end

    handler_params = handler_params |> Map.put_new(:state, true)

    args =
      if handler_params.state do
        args ++ [state |> Map.fetch!(:internal_state)]
      else
        args
      end

    module |> apply(callback, args) |> parse_callback_result(module, callback, handler_params)
  end

  @spec handle_callback_result(
          callback_return_t,
          callback :: atom,
          module,
          handler_params_t,
          state_t
        ) :: Type.stateful_try_t(state_t)
  defp handle_callback_result(result, callback, handler_module, handler_params, state) do
    {result, state} =
      case result do
        {result, {:state, new_internal_state}} ->
          {result, state |> Map.put(:internal_state, new_internal_state)}

        {result, :no_state} ->
          {result, state}
      end

    with {{:ok, actions}, state} <- {result, state},
         {:ok, state} <-
           actions
           |> exec_handle_actions(callback, handler_module, handler_params, state) do
      {:ok, state}
    end
  end

  @spec exec_handle_actions(list, callback :: atom, module, handler_params_t, state_t) ::
          Type.stateful_try_t(state_t)
  defp exec_handle_actions(actions, callback, handler_module, handler_params, state) do
    with {:ok, state} <- actions |> handler_module.handle_actions(callback, handler_params, state) do
      {:ok, state}
    else
      {{:error, reason}, state} ->
        warn("""
        Error while handling actions returned by callback #{inspect(callback)}
        """)

        {{:error, {:error_handling_actions, reason}}, state}
    end
  end

  @spec parse_callback_result(callback_return_t | any, module, callback :: atom, handler_params_t) ::
          {:ok, Type.stateful_try_t(list, internal_state_t)}
          | {:error, {:invalid_callback_result, details :: Keyword.t()}}
  defp parse_callback_result({:ok, new_internal_state}, module, cb, params),
    do: parse_callback_result({{:ok, []}, new_internal_state}, module, cb, params)

  defp parse_callback_result({{:ok, actions}, new_internal_state}, _module, _cb, _params) do
    {{:ok, actions}, {:state, new_internal_state}}
  end

  defp parse_callback_result({{:error, reason}, new_internal_state}, module, cb, %{state: true}) do
    warn_error(
      """
      Callback #{inspect(cb)} from module #{inspect(module)} returned an error
      Internal state: #{inspect(new_internal_state)}
      """,
      reason
    )

    {{:error, reason}, {:state, new_internal_state}}
  end

  defp parse_callback_result({:error, reason}, module, cb, %{state: false}) do
    warn_error(
      """
      Callback #{inspect(cb)} from module #{inspect(module)} returned an error
      """,
      reason
    )

    {{:error, reason}, :no_state}
  end

  defp parse_callback_result(result, module, cb, _params) do
    raise CallbackError, kind: :bad_return, callback: {module, cb}, val: result
  end
end
