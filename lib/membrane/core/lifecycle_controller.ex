defmodule Membrane.Core.LifecycleController do
  @moduledoc false

  alias Membrane.Core.{Component, Message, Parent}
  alias Membrane.SetupError

  require Membrane.Core.Message
  require Membrane.Logger

  @type setup_operation :: :incomplete | :complete

  @spec handle_setup_operation(setup_operation(), Component.state()) ::
          Component.state()
  def handle_setup_operation(operation, state) do
    :ok = assert_operation_allowed!(operation, state.setup_incomplete?)

    case operation do
      :incomplete ->
        Membrane.Logger.debug("Component deferred initialization")
        %{state | setup_incomplete?: true}

      :complete ->
        complete_setup(state)
    end
  end

  @spec complete_setup(Component.state()) :: Component.state()
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

  @spec assert_operation_allowed!(setup_operation(), boolean()) :: :ok | no_return()
  defp assert_operation_allowed!(:incomplete, true) do
    raise SetupError, """
    Action {:setup, :incomplete} was returned more than once
    """
  end

  defp assert_operation_allowed!(:complete, false) do
    raise SetupError, """
    Action {:setup, :complete} was returned, but setup is already completed
    """
  end

  defp assert_operation_allowed!(_operation, _status), do: :ok
end
