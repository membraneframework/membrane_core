defmodule Membrane.Core.Parent.Supervisor do
  @moduledoc false

  use GenServer

  alias Membrane.Core.Parent.ChildrenSupervisor

  require Membrane.Core.Message, as: Message
  require Membrane.Logger

  @spec go_brrr(
          :start_link | :start,
          (children_supervisor :: pid() -> {:ok, pid()} | {:error, reason :: any()}),
          Membrane.Core.Observability.setup_fun()
        ) :: {:ok, pid()} | {:error, reason :: any()}
  def go_brrr(method, start_fun, setup_observability) do
    # Not doing start_link here is a nasty hack to avoid the current process becoming
    # a 'parent process' (in the OTP meaning) of the spawned supervisor. Exit signals from
    # 'parent processes' are not received in `handle_info`, but `terminate` is called immediately,
    # what is unwanted here, as the supervisor has to make sure that all the children exit.
    # After that happens, the supervisor exits as well, so it follows the OTP conventions anyway.
    process_opts = if method == :start_link, do: [spawn_opt: [:link]], else: []

    with {:ok, pid} <-
           GenServer.start(__MODULE__, {start_fun, setup_observability, self()}, process_opts) do
      receive do
        Message.new(:parent_spawned, parent) -> {:ok, pid, parent}
      end
    end
  end

  @impl true
  def init({start_fun, setup_observability, reply_to}) do
    Process.flag(:trap_exit, true)
    {:ok, children_supervisor} = ChildrenSupervisor.start_link()

    with {:ok, parent} <- start_fun.(children_supervisor) do
      setup_observability.(pid: parent, utility: "Supervisor")
      Message.send(reply_to, :parent_spawned, parent)
      {:ok, %{parent: {:alive, parent}, children_supervisor: children_supervisor}}
    else
      {:error, reason} ->
        Process.exit(children_supervisor, :shutdown)
        receive do: ({:EXIT, ^children_supervisor, _reason} -> :ok)
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:which_children, _from, state) do
    reply =
      [{ChildrenSupervisor, state.children_supervisor, :supervisor, ChildrenSupervisor}] ++
        case state.parent do
          {:alive, pid} -> [{:parent, pid, :worker, []}]
          {:exited, _reason} -> []
        end

    {:reply, reply, state}
  end

  @impl true
  def handle_info(Message.new(:child_death, _args) = message, %{parent: {:alive, parent}} = state) do
    send(parent, message)
    {:noreply, state}
  end

  @impl true
  def handle_info(Message.new(:child_death, _args), state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{parent: {:alive, pid}} = state) do
    Membrane.Logger.debug(
      "Parent supervisor: parent exited with reason #{inspect(reason)}, stopping children supervisor"
    )

    Process.exit(state.children_supervisor, :shutdown)
    {:noreply, %{state | parent: {:exited, reason}}}
  end

  @impl true
  def handle_info(
        {:EXIT, pid, :normal},
        %{children_supervisor: pid, parent: {:exited, parent_exit_reason}} = state
      ) do
    Membrane.Logger.debug("Parent supervisor: children supervisor exited. Exiting.")

    reason =
      case parent_exit_reason do
        :normal -> :normal
        :shutdown -> :shutdown
        {:shutdown, reason} -> {:shutdown, reason}
        _other -> :shutdown
      end

    {:stop, reason, state}
  end

  @impl true
  def handle_info(
        {:EXIT, pid, reason},
        %{children_supervisor: pid, parent: {:alive, _parent_pid}} = state
      ) do
    Membrane.Logger.debug(
      "Parent supervisor: children supervisor failure, reason: #{inspect(reason)}. Exiting."
    )

    {:stop, {:shutdown, :children_supervisor_failed}, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, %{parent: {:alive, parent_pid}} = state) do
    Membrane.Logger.debug("Parent supervisor: got exit from a linked process, stopping parent")
    Process.exit(parent_pid, reason)
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    Membrane.Logger.debug(
      "Parent supervisor: got exit from a linked process, parent already dead, waiting for children supervisor to exit"
    )

    {:noreply, state}
  end
end
