defmodule Membrane.Core.LifecycleController do
  @moduledoc false

  alias Membrane.Core.{Component, Message, Parent}
  alias Membrane.SetupError

  require Membrane.Core.Message
  require Membrane.Logger

  @type setup_operation_t :: :incomplete | :complete

  @spec handle_setup_operation(setup_operation_t(), atom(), Component.state_t()) ::
          Component.state_t()
  def handle_setup_operation(operation, callback, state) do
    :ok = assert_operation_allowed!(operation, callback, state.setup_incomplete?)

    case operation do
      :incomplete ->
        Membrane.Logger.debug("Component deferred initialization")
        %{state | setup_incomplete?: true}

      :complete ->
        complete_setup(state)
    end
  end

  @spec complete_setup(Component.state_t()) :: Component.state_t()
  def complete_setup(state) do
    state = %{state | initialized?: true, setup_incomplete?: false}
    Membrane.Logger.debug("Component initialized")

    cond do
      Component.is_pipeline?(state) ->
        Parent.LifecycleController.handle_playing(state)

      Component.is_child?(state) ->
        Message.send(state.parent_pid, :initialized, state.name)
        state
    end
  end

  @spec assert_operation_allowed!(setup_operation_t(), atom(), boolean()) :: :ok | no_return()
  defp assert_operation_allowed!(:incomplete, callback, true) do
    raise SetupError, """
    Action {:setup, :incomplete} was returned more than once
    """
  end

  defp assert_operation_allowed!(:complete, callback, false) do
    raise SetupError, """
    Action {:setup, :complete} was returned from callback #{inspect(callback)}, but setup is already completed
    """
  end

  defp assert_operation_allowed!(_operation, _callback, _status), do: :ok
end
