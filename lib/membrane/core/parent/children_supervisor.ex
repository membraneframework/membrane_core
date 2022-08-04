defmodule Membrane.Core.Parent.ChildrenSupervisor do
  @moduledoc false

  use GenServer

  require Membrane.Core.Message, as: Message
  require Membrane.Logger

  @spec start_link() :: {:ok, pid()}
  def start_link() do
    # Not doing start_link here is a nasty hack to avoid the current process becoming
    # a 'parent process' (in the OTP meaning) of the spawned supervisor. Exit signals from
    # 'parent processes' are not received in `handle_info`, but `terminate` is called immediately,
    # what is unwanted here, as the supervisor has to make sure that all the children exit.
    # After that happens, the supervisor exits as well, so it follows the OTP conventions anyway.
    GenServer.start(__MODULE__, self(), spawn_opt: [:link])
  end

  @spec start_child(
          supervisor_pid,
          name :: Membrane.Child.name_t(),
          (() -> {:ok, child_pid} | {:ok, supervisor_pid, child_pid} | {:error, reason :: any()})
        ) ::
          {:ok, child_pid} | {:error, reason :: any()}
        when child_pid: pid(), supervisor_pid: pid()
  def start_child(supervisor, name, start_fun) do
    Message.call!(supervisor, :start_child, [name, start_fun])
  end

  @impl true
  def init(parent_supervisor) do
    Process.flag(:trap_exit, true)
    {:ok, %{parent_supervisor: {:alive, parent_supervisor}, children: %{}}}
  end

  @impl true
  def handle_call(Message.new(:start_child, [name, start_fun]), _from, state) do
    case start_fun.() do
      {:ok, child_pid} ->
        {:reply, {:ok, child_pid},
         put_in(state, [:children, child_pid], %{name: name, type: :worker})}

      {:ok, supervisor_pid, child_pid} ->
        {:reply, {:ok, child_pid},
         put_in(state, [:children, supervisor_pid], %{name: name, type: :supervisor})}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:which_children, _from, state) do
    reply = Enum.map(state.children, fn {pid, data} -> {data.name, pid, data.type, []} end)
    {:reply, reply, state}
  end

  @impl true
  def handle_info(Message.new(:setup_observability, setup_observability), state) do
    setup_observability.(utility: "Children supervisor")
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:EXIT, pid, _reason},
        %{parent_supervisor: {:alive, pid}, children: children} = state
      )
      when children == %{} do
    Membrane.Logger.debug("Children supervisor: exiting")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{parent_supervisor: {:alive, pid}} = state) do
    Membrane.Logger.debug(
      "Children supervisor: got exit request from parent, reason: #{inspect(reason)}, shutting down children"
    )

    state.children |> Map.keys() |> Enum.each(&Process.exit(&1, {:shutdown, :parent_crash}))
    {:noreply, %{state | parent_supervisor: :exit_requested}}
  end

  @impl true
  def handle_info(
        {:EXIT, pid, _reason},
        %{parent_supervisor: :exit_requested} = state
      ) do
    {_data, state} = pop_in(state, [:children, pid])

    if state.children == %{} do
      Membrane.Logger.debug("Children supervisor: exiting")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    {data, state} = pop_in(state, [:children, pid])

    case state.parent_supervisor do
      {:alive, pid} -> Message.send(pid, :child_death, [data.name, reason])
      _other -> :ok
    end

    {:noreply, state}
  end
end
