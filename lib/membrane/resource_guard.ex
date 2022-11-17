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

        Membrane.ResourceGuard.register(ctx.resource_guard, fn ->
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
  Function returns a tag of the registered cleanup function. Tag can be passed
  under a `:tag` key in `opts`. Many functions can be registered with the same tag.
  If there is no `:tag` key in `opts`, tag will be result of `make_ref()`.
  """
  @spec register(
          t,
          (() -> any),
          opts :: [tag: any, timeout: milliseconds :: non_neg_integer]
        ) :: tag
        when tag: any()
  def register(resource_guard, cleanup_function, opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :tag, &make_ref/0)
    Message.send(resource_guard, :register, [cleanup_function, opts])
    Keyword.get(opts, :tag)
  end

  @doc """
  Unregisters a resource cleanup function from the resource guard.

  All cleanup functions with tag `tag` are deleted.
  """
  @spec unregister(t, tag :: any) :: :ok
  def unregister(resource_guard, tag) do
    Message.send(resource_guard, :unregister, tag)
    :ok
  end

  @doc """
  Executes all cleanup functions registered in the resource gurard.
  """
  @spec cleanup(t) :: :ok
  def cleanup(resource_guard) do
    Message.send(resource_guard, :cleanup_all)
    :ok
  end

  @doc """
  Executes cleanup functions registered with the specifc tag.

  If many cleanup functions are registered with the same tag, all of them are executed.
  """
  @spec cleanup(t, tag :: any) :: :ok
  def cleanup(resource_guard, tag) do
    Message.send(resource_guard, :cleanup, tag)
    :ok
  end

  @impl true
  def init(owner_pid) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner_pid)
    {:ok, %{guards: [], monitor: monitor}}
  end

  @impl true
  def handle_info(Message.new(:register, [function, opts]), state) do
    tag = Keyword.fetch!(opts, :tag)
    timeout = Keyword.get(opts, :timeout, 5000)
    {:noreply, %{state | guards: [{function, tag, timeout} | state.guards]}}
  end

  @impl true
  def handle_info(Message.new(:unregister, tag), state) do
    guards =
      Enum.reject(state.guards, fn
        {_function, ^tag, _timeout} -> true
        _other -> false
      end)

    {:noreply, %{state | guards: guards}}
  end

  @impl true
  def handle_info(Message.new(:cleanup_all), state) do
    do_cleanup_all(state.guards)
    {:noreply, %{state | guards: []}}
  end

  @impl true
  def handle_info(Message.new(:cleanup, tag), state) do
    guards =
      Enum.reject(state.guards, fn
        {function, ^tag, timeout} ->
          do_cleanup(function, tag, timeout)
          true

        _other ->
          false
      end)

    {:noreply, %{state | guards: guards}}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state) do
    do_cleanup_all(state.guards)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp do_cleanup_all(guards) do
    for {function, tag, timeout} <- guards do
      do_cleanup(function, tag, timeout)
    end
  end

  defp do_cleanup(function, tag, timeout) do
    {:ok, task} = Task.start_link(function)

    receive do
      {:EXIT, ^task, reason} -> reason
    after
      timeout ->
        Membrane.Logger.error("Cleanup of resource with tag: #{inspect(tag)} timed out, killing")
        Process.unlink(task)
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
          "Error cleaning up resource with tag: #{inspect(tag)}, due to: #{inspect(reason)}"
        )
    end

    :ok
  end
end
