defmodule Membrane.ResourceGuard do
  @moduledoc """
  Utility for handling resources that must be cleaned up after use.

  This utility uses a separate process that allows registering functions
  that are called when the owner process (passed to `start_link/1`) dies for
  any reason. Each Membrane component spawns its resource guard on startup
  and provides it via callback context.

  ### Example

      def handle_setup(ctx, state) do
        resource = MyResource.create()

        Membrane.ResourceGuard.register_resource(ctx.resource_guard, fn ->
          MyResource.cleanup(resource)
        end)

        {:ok, %{state | my_resource: resource}}
      end

  """
  use GenServer

  require Membrane.Core.Message, as: Message
  require Membrane.Logger

  @type t :: pid()

  @spec start_link(owner_pid :: pid) :: {:ok, t}
  def start_link(owner_pid \\ self()) do
    GenServer.start(__MODULE__, owner_pid, spawn_opt: [:link])
  end

  @doc """
  Registers a resource cleanup function in the resource guard.

  Registered functions are called in the order reverse to the registration order.
  A return value of a registered function is ignored. If a `name` is passed,
  the function can be cleaned up manually with `cleanup_resource/2`. Many
  functions can be registered with the same name.
  """
  @spec register_resource(
          t,
          (() -> any),
          opts :: [name: term, timeout: milliseconds :: non_neg_integer]
        ) :: :ok
  def register_resource(resource_guard, cleanup_function, opts \\ []) do
    Message.send(resource_guard, :register_resource, [cleanup_function, opts])
    :ok
  end

  @doc """
  Cleans up a named resource manually.

  If many resources are registered with the name, all of them are cleaned up.
  """
  @spec cleanup_resource(t, name :: any) :: :ok
  def cleanup_resource(resource_guard, name) do
    Message.send(resource_guard, :cleanup_resource, name)
    :ok
  end

  @impl true
  def init(owner_pid) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner_pid)
    {:ok, %{guards: [], monitor: monitor}}
  end

  @impl true
  def handle_info(Message.new(:register_resource, [function, opts]), state) do
    name = Keyword.get(opts, :name)
    timeout = Keyword.get(opts, :timeout, 5000)
    {:noreply, %{state | guards: [{function, name, timeout} | state.guards]}}
  end

  @impl true
  def handle_info(Message.new(:cleanup_resource, name), state) do
    guards =
      Enum.reject(state.guards, fn
        {function, ^name, timeout} ->
          cleanup(function, name, timeout)
          true

        _other ->
          false
      end)

    {:noreply, %{state | guards: guards}}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state) do
    Enum.each(state.guards, fn {function, name, timeout} -> cleanup(function, name, timeout) end)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp cleanup(function, name, timeout) do
    {:ok, task} = Task.start_link(function)

    receive do
      {:EXIT, ^task, reason} -> reason
    after
      timeout ->
        Membrane.Logger.error("Cleanup of resource #{inspect(name)} timed out, killing")
        Process.exit(task, :kill)
        :normal
    end
    |> case do
      :normal ->
        :ok

      :shutdown ->
        :ok

      {:shutdown, _reason} ->
        :ok

      reason ->
        Membrane.Logger.error(
          "Error cleaning up resource #{inspect(name)}, got error #{inspect(reason)}"
        )
    end

    :ok
  end
end
