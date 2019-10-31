defmodule Membrane.Core.Pipeline.ActionHandler do
  @moduledoc false
  use Membrane.Core.CallbackHandler
  use Membrane.Log, tags: :core

  alias Membrane.CallbackError
  alias Membrane.ParentSpec
  alias Membrane.Core.Parent

  @impl CallbackHandler
  # Deprecation
  def handle_actions(%ParentSpec{} = spec, :handle_init, params, state) do
    warn("""
    Returning bare spec from `handle_init` is deprecated.
    Return `{{:ok, spec: spec}, state}` instead.
    Found in `#{inspect(state.module)}.handle_init/1`.
    """)

    super([spec: spec], :handle_init, params, state)
  end

  @impl CallbackHandler
  def handle_actions(actions, callback, params, state) do
    super(actions, callback, params, state)
  end

  @impl CallbackHandler
  def handle_action(action, callback, params, state) do
    with {:ok, state} <- do_handle_action(action, callback, params, state) do
      {:ok, state}
    else
      {{:error, :invalid_action}, state} ->
        raise CallbackError,
          kind: :invalid_action,
          action: action,
          callback: {state.module, callback}

      error ->
        error
    end
  end

  defp do_handle_action({action, _args}, :handle_init, _params, state)
       when action not in [:spec] do
    {{:error, :invalid_action}, state}
  end

  defp do_handle_action({:forward, {elementname, message}}, _cb, _params, state) do
    Parent.ChildLifeController.handle_forward(elementname, message, state)
  end

  defp do_handle_action({:spec, spec = %ParentSpec{}}, _cb, _params, state) do
    with {{:ok, _children}, state} <- Parent.ChildLifeController.handle_spec(spec, state),
         do: {:ok, state}
  end

  defp do_handle_action({:remove_child, children}, _cb, _params, state) do
    Parent.ChildLifeController.handle_remove_child(children, state)
  end

  defp do_handle_action(action, callback, _params, state) do
    raise CallbackError, kind: :invalid_action, action: action, callback: {state.module, callback}
  end
end
