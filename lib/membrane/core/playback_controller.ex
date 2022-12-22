defmodule Membrane.Core.PlaybackController do
  @moduledoc false

  alias Membrane.Core.{Component, Message, Parent}
  alias Membrane.PlaybackError

  require Membrane.Core.Message
  require Membrane.Logger

  @type setup_operation_t :: :incomplete | :complete

  @spec handle_setup_operation(setup_operation_t(), atom(), Component.state_t()) ::
          Component.state_t()
  def handle_setup_operation(operation, callback, state) do
    :ok = assert_operation_allowed(operation, callback, state.setup_incomplete_returned?)

    case operation do
      :incomplete ->
        Membrane.Logger.debug("Component deferred initialization")
        %{state | setup_incomplete_returned?: true}

      :complete ->
        complete_setup(state)
    end
  end

  @spec complete_setup(Component.state_t()) :: Component.state_t()
  def complete_setup(state) do
    state = %{state | initialized?: true, setup_incomplete_returned?: false}

    cond do
      Component.is_pipeline?(state) ->
        Membrane.Logger.debug("Pipeline initialized")
        Parent.LifecycleController.handle_playing(state)

      Component.is_bin?(state) ->
        Membrane.Logger.debug("Bin initialized")
        Message.send(state.parent_pid, :initialized, state.name)
        state

      Component.is_element?(state) ->
        Membrane.Logger.debug("Element initialized")
        Message.send(state.parent_pid, :initialized, state.name)
        state
    end
  end

  @spec assert_operation_allowed(setup_operation_t(), atom(), boolean()) :: :ok | no_return()
  defp assert_operation_allowed(:incomplete, :handle_setup, true) do
    raise PlaybackError, """
    Action {:setup, :incomplete} was returned mutliple times from :handle_setup
    """
  end

  defp assert_operation_allowed(:incomplete, callback, _status) when callback != :handle_setup do
    raise PlaybackError, """
    Action {:setup, :incomplete} was returned from callback #{inspect(callback)}, but it can be returend only
    from :handle_setup
    """
  end

  defp assert_operation_allowed(:complete, callback, false) do
    raise PlaybackError, """
    Action {:setup, :complete} was returned from callback #{inspect(callback)}, but setup is already completed
    """
  end

  defp assert_operation_allowed(_operation, _callback, _status), do: :ok
end
