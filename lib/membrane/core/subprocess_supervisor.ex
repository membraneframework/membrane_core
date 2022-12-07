defmodule Membrane.Core.SubprocessSupervisor do
  @moduledoc false
  # Supervisor that can be used by components to spawn and supervise whatever child processes
  # they want - another components or some utilities. The supervisor doesn't restart any
  # processes - it only makes sure that they terminate properly and informs the parent
  # component about their termination.

  use Bunch
  use GenServer

  alias Membrane.Core.Observability

  require Membrane.Core.Message, as: Message
  require Membrane.Logger

  @spec start_link!() :: pid()
  def start_link!() do
    # Not doing start_link here is a nasty hack to avoid the current process becoming
    # a 'parent process' (in the OTP meaning) of the spawned supervisor. Exit signals from
    # 'parent processes' are not received in `handle_info`, but `terminate` is called immediately,
    # what is unwanted here, as the supervisor has to make sure that all the children exit.
    # After that happens, the supervisor exits as well, so it follows the OTP conventions anyway.
    {:ok, pid} = GenServer.start(__MODULE__, self(), spawn_opt: [:link])
    pid
  end

  @doc """
  Starts a Membrane component under the supervisor
  """
  @spec start_component(
          supervisor_pid,
          name :: Membrane.Child.name_t(),
          (supervisor_pid, parent_supervisor_pid -> {:ok, child_pid} | {:error, reason :: any()})
        ) ::
          {:ok, child_pid} | {:error, reason :: any()}
        when child_pid: pid(), supervisor_pid: pid(), parent_supervisor_pid: pid
  def start_component(supervisor, name, start_fun) do
    Message.call!(supervisor, :start_component, [name, start_fun])
  end

  @doc """
  Starts a utility process under the supervisor.

  The process will be terminated when the parent component dies.
  """
  @spec start_utility(
          supervisor_pid :: pid,
          Supervisor.child_spec() | {module(), term()} | module()
        ) ::
          Supervisor.on_start_child()
  def start_utility(supervisor, child_spec) do
    child_spec = Supervisor.child_spec(child_spec, [])
    Message.call!(supervisor, :start_utility, child_spec)
  end

  @doc """
  Like `start_utility/2`, but links the spawned utility to the calling process.
  """
  @spec start_link_utility(
          supervisor_pid :: pid,
          Supervisor.child_spec() | {module(), term()} | module()
        ) ::
          Supervisor.on_start_child()
  def start_link_utility(supervisor, child_spec) do
    result = start_utility(supervisor, child_spec)

    case result do
      {:ok, pid, _info} -> Process.link(pid)
      {:ok, pid} -> Process.link(pid)
      _error -> :ok
    end

    result
  end

  @doc """
  Sets the calling Membrane component as the parent component for children and utilities
  spawned with the supervisor.
  """
  @spec set_parent_component(
          supervisor_pid :: pid,
          observability_config :: Observability.config()
        ) :: :ok
  def set_parent_component(supervisor, observability_config) do
    Message.send(supervisor, :set_parent_component, [
      self(),
      observability_config
    ])

    :ok
  end

  @impl true
  def init(parent_process) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       parent_component: nil,
       parent_process: {:alive, parent_process},
       children: %{}
     }}
  end

  @impl true
  def handle_call(Message.new(:start_component, [name, start_fun]), _from, state) do
    subprocess_supervisor = start_link!()

    with {:ok, child_pid} <- start_fun.(subprocess_supervisor, self()) do
      state =
        state
        |> put_in([:children, child_pid], %{
          name: name,
          type: :worker,
          supervisor_pid: subprocess_supervisor,
          role: :component
        })
        |> put_in([:children, subprocess_supervisor], %{
          name: {__MODULE__, name},
          type: :supervisor,
          child_pid: child_pid,
          role: :subprocess_supervisor
        })

      {:reply, {:ok, child_pid}, state}
    else
      {:error, reason} ->
        Process.exit(subprocess_supervisor, :shutdown)
        receive do: ({:EXIT, ^subprocess_supervisor, _reason} -> :ok)
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(Message.new(:start_utility, child_spec), _from, state) do
    try do
      {m, f, a} = child_spec.start
      apply(m, f, a)
    rescue
      error -> error
    catch
      error -> error
    end
    |> case do
      {:ok, pid, _info} = result -> {:ok, pid, result}
      {:ok, pid} = result -> {:ok, pid, result}
      error -> error
    end
    |> case do
      {:ok, pid, result} ->
        state =
          put_in(state, [:children, pid], %{
            name: child_spec.id,
            type: Map.get(child_spec, :type, :worker),
            role: :utility
          })

        {:reply, result, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:which_children, _from, state) do
    reply = Enum.map(state.children, fn {pid, data} -> {data.name, pid, data.type, []} end)
    {:reply, reply, state}
  end

  @impl true
  def handle_info(Message.new(:set_parent_component, [pid, observability_config]), state) do
    Membrane.Core.Observability.setup(observability_config, "subprocess supervisor")
    {:noreply, %{state | parent_component: pid}}
  end

  @impl true
  def handle_info(
        {:EXIT, pid, _reason},
        %{parent_process: {:alive, pid}, children: children} = state
      )
      when children == %{} do
    Membrane.Logger.debug("exiting")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{parent_process: {:alive, pid}} = state) do
    Membrane.Logger.debug(
      "got exit request from parent, reason: #{inspect(reason)}, shutting down children"
    )

    Enum.each(state.children, fn {pid, %{role: role}} ->
      if role != :subprocess_supervisor, do: Process.exit(pid, :shutdown)
    end)

    {:noreply, %{state | parent_process: :exit_requested}}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    {data, state} = pop_in(state, [:children, pid])
    handle_exit(data, reason, state)

    case state do
      %{parent_process: :exit_requested, children: children} when children == %{} ->
        {:stop, :normal, state}

      state ->
        {:noreply, state}
    end
  end

  defp handle_exit(%{role: :subprocess_supervisor} = data, reason, state) do
    case Map.fetch(state.children, data.child_pid) do
      {:ok, child_data} ->
        raise "Subprocess supervisor failure #{inspect(child_data.name)}, reason: #{inspect(reason)}"

      :error ->
        :ok
    end
  end

  defp handle_exit(%{role: :component} = data, reason, state) do
    Process.exit(data.supervisor_pid, :shutdown)
    Message.send(state.parent_component, :child_death, [data.name, reason])
  end

  defp handle_exit(%{role: :utility}, _reason, _state) do
    :ok
  end

  # Clause handling the case when child start function returns error
  # and we don't know its PID, but we still receive exit signal from it.
  defp handle_exit(nil, _reason, _state) do
    :ok
  end
end
