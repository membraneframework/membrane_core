defmodule Membrane.Core.Pipeline.Supervisor do
  @moduledoc false

  use GenServer

  alias Membrane.Core.SubprocessSupervisor

  require Membrane.Core.Message, as: Message
  require Membrane.Logger

  @spec run(
          :start_link | :start,
          name :: term,
          (subprocess_supervisor :: pid() -> {:ok, pid()} | {:error, reason :: any()})
        ) :: {:ok, supervisor_pid :: pid(), pipeline_pid :: pid()} | {:error, reason :: any()}
  def run(method, name, start_fun) do
    # Not doing start_link here is a nasty hack to avoid the current process becoming
    # a 'pipeline process' (in the OTP meaning) of the spawned supervisor. Exit signals from
    # 'pipeline processes' are not received in `handle_info`, but `terminate` is called immediately,
    # what is unwanted here, as the supervisor has to make sure that all the children exit.
    # After that happens, the supervisor exits as well, so it follows the OTP conventions anyway.
    process_opts = if method == :start_link, do: [spawn_opt: [:link]], else: []

    with {:ok, pid} <-
           GenServer.start(__MODULE__, {start_fun, name, self()}, process_opts) do
      receive do
        Message.new(:pipeline_spawned, pipeline) -> {:ok, pid, pipeline}
      end
    end
  end

  @impl true
  def init({start_fun, name, reply_to}) do
    Process.flag(:trap_exit, true)
    subprocess_supervisor = SubprocessSupervisor.start_link!()

    with {:ok, pipeline} <- start_fun.(subprocess_supervisor) do
      Membrane.Core.Observability.setup(
        %{name: name, component_type: :pipeline, pid: pipeline},
        "Pipeline supervisor"
      )

      Message.send(reply_to, :pipeline_spawned, pipeline)
      {:ok, %{pipeline: {:alive, pipeline}, subprocess_supervisor: subprocess_supervisor}}
    else
      {:error, reason} ->
        Process.exit(subprocess_supervisor, :shutdown)
        receive do: ({:EXIT, ^subprocess_supervisor, _reason} -> :ok)
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:which_children, _from, state) do
    reply =
      [{SubprocessSupervisor, state.subprocess_supervisor, :supervisor, SubprocessSupervisor}] ++
        case state.pipeline do
          {:alive, pid} -> [{:pipeline, pid, :worker, []}]
          {:exited, _reason} -> []
        end

    {:reply, reply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{pipeline: {:alive, pid}} = state) do
    Membrane.Logger.debug(
      "got exit from pipeline with reason #{inspect(reason)}, stopping subprocess supervisor"
    )

    Process.exit(state.subprocess_supervisor, :shutdown)
    {:noreply, %{state | pipeline: {:exited, reason}}}
  end

  @impl true
  def handle_info(
        {:EXIT, pid, :normal},
        %{subprocess_supervisor: pid, pipeline: {:exited, pipeline_exit_reason}} = state
      ) do
    Membrane.Logger.debug("got exit from subprocess supervisor, exiting")

    reason =
      case pipeline_exit_reason do
        :normal -> :normal
        :shutdown -> :shutdown
        {:shutdown, reason} -> {:shutdown, reason}
        _other -> :shutdown
      end

    {:stop, reason, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{
        subprocess_supervisor: pid,
        pipeline: {:alive, _pipeline_pid}
      }) do
    raise "Subprocess supervisor failure, reason: #{inspect(reason)}"
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, %{pipeline: {:alive, pipeline_pid}} = state) do
    Membrane.Logger.debug("got exit from a linked process, stopping pipeline")
    Process.exit(pipeline_pid, reason)
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    Membrane.Logger.debug(
      "got exit from a linked process, pipeline already dead, waiting for subprocess supervisor to exit"
    )

    {:noreply, state}
  end
end
