defmodule Membrane.Core.Pipeline do
  @moduledoc false
  use GenServer

  require Membrane.Logger
  require Membrane.Element

  alias __MODULE__.{ActionHandler, State}
  alias Membrane.Clock
  alias Membrane.Core.CallbackHandler
  alias Membrane.Core.Parent.MessageDispatcher

  @impl GenServer
  def init(module) when is_atom(module) do
    init({module, module |> Bunch.Module.struct()})
  end

  @impl GenServer
  def init(%module{} = pipeline_options) do
    init({module, pipeline_options})
  end

  @impl GenServer
  def init({module, pipeline_options}) do
    :ok = Membrane.Logger.set_prefix("pipeline@#{:erlang.pid_to_list(self())}")
    {:ok, clock} = Clock.start_link(proxy: true)

    state = %State{
      module: module,
      synchronization: %{
        clock_proxy: clock,
        clock_provider: %{clock: nil, provider: nil, choice: :auto},
        timers: %{}
      }
    }

    with {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_init,
             ActionHandler,
             %{state: false},
             [pipeline_options],
             state
           ) do
      {:ok, state}
    end
  end

  @impl GenServer
  def handle_info(message, state) do
    MessageDispatcher.handle_message(message, state)
  end

  @impl GenServer
  def terminate(reason, state) do
    :ok = state.module.handle_shutdown(reason, state.internal_state)
  end
end
