defmodule Membrane.Core.PlaybackController do
  alias Membrane.Core.{Component, Message, Parent}

  require Membrane.Core.Message
  require Membrane.Logger

  @type setup_operation_t :: :defer | :complete

  @spec handle_setup_operation(setup_operation_t(), atom(), Component.state_t()) ::
          Component.state_t()
  def handle_setup_operation(operation, callback, state) do
    :ok = assert_operation_allowed(operation, callback, state.setup_deferred?)

    case operation do
      :defer -> defer_setup(state)
      :complete -> complete_setup(state)
    end
  end

  @spec defer_setup(Component.state_t()) :: Component.state_t()
  def defer_setup(state) do
    %{state | setup_deferred?: true}
  end

  @spec complete_setup(Component.state_t()) :: Component.state_t()
  def complete_setup(state) do
    state = %{state | initialized?: true, setup_deferred?: false}

    cond do
      Component.is_pipeline?(state) ->
        Membrane.Logger.debug("Pipeline initialized")

        with %{playing_requested?: true} <- state do
          Parent.LifecycleController.handle_playing(state)
        end

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
  defp assert_operation_allowed(operation, callback, deferred?) do
    do_assert(operation, callback, deferred?)
  end

  defp do_assert(:defer, :handle_setup, true) do
    raise "Action {:setup, :defer} was returned from handle_setup/4, but setup has already been deferred"
  end

  defp do_assert(:defer, callback, _status) when callback != :handle_setup do
    raise "Action {:setup, :defer} was returned from callback #{inspect(callback)}, but it can be returend only from :handle_setup"
  end

  defp do_assert(:complete, callback, _status) when callback in [:handle_init, :handle_setup] do
    raise "Action {:setup, :complete} cannot be returned from #{inspect(callback)}"
  end

  defp do_assert(:complete, callback, false) do
    raise "Action {:setup, :complete} was returned from callback #{inspect(callback)}, but setup is not deferred"
  end

  defp do_assert(_operation, _callback, _status), do: :ok
end
