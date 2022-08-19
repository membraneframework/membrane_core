defmodule Membrane.Core.ChildrenSupervisor do
  @moduledoc false

  use Bunch
  use GenServer

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

  @spec start_child(
          supervisor_pid,
          name :: Membrane.Child.name_t(),
          (supervisor_pid -> {:ok, child_pid} | {:error, reason :: any()})
        ) ::
          {:ok, child_pid} | {:error, reason :: any()}
        when child_pid: pid(), supervisor_pid: pid()
  def start_child(supervisor, name, start_fun) do
    Message.call!(supervisor, :start_child, [name, start_fun])
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
  def handle_call(Message.new(:start_child, [name, start_fun]), _from, state) do
    children_supervisor = start_link!()

    with {:ok, child_pid} <- start_fun.(children_supervisor) do
      state =
        state
        |> put_in([:children, child_pid], %{
          name: name,
          type: :worker,
          supervisor_pid: children_supervisor
        })
        |> put_in([:children, children_supervisor], %{
          name: {__MODULE__, name},
          type: :supervisor,
          child_pid: child_pid
        })

      {:reply, {:ok, child_pid}, state}
    else
      {:error, reason} ->
        Process.exit(children_supervisor, :shutdown)
        receive do: ({:EXIT, ^children_supervisor, _reason} -> :ok)
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:which_children, _from, state) do
    reply = Enum.map(state.children, fn {pid, data} -> {data.name, pid, data.type, []} end)
    {:reply, reply, state}
  end

  @impl true
  def handle_info(Message.new(:set_parent_component, [pid, setup_observability]), state) do
    setup_observability.(utility: "children supervisor")
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

    Enum.each(state.children, fn {pid, %{type: type}} ->
      if type == :worker, do: Process.exit(pid, {:shutdown, :parent_crash})
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

  defp handle_exit(%{type: :supervisor} = data, reason, state) do
    case Map.fetch(state.children, data.child_pid) do
      {:ok, child_data} ->
        raise "Children supervisor failure #{inspect(child_data.name)}, reason: #{inspect(reason)}"

      :error ->
        :ok
    end
  end

  defp handle_exit(%{type: :worker} = data, reason, state) do
    Process.exit(data.supervisor_pid, :shutdown)
    Message.send(state.parent_component, :child_death, [data.name, reason])
  end
end
