defmodule Membrane.Log.Router do
  @moduledoc deprecated: "Use Elixir `Logger` instead"
  @moduledoc """
  Defines a router that dispatches logs to instances of `Membrane.Log.Logger.Base`
  """
  use GenServer

  alias Membrane.Log.Supervisor

  @doc """
  Starts router as a separate process.

  Options are passed to `Supervisor.start_link/3`.
  """
  @spec start_link({any, GenServer.options()}) :: GenServer.on_start()
  def start_link({config, process_options}) do
    loggers = config |> Keyword.get(:loggers, [])
    GenServer.start_link(__MODULE__, loggers, process_options)
  end

  @doc """
  Sends asynchronous call to the router, requesting it to forward log message
  to appropriate loggers.

  This functions assumes that passed log has level equal or greater than global
  level.
  """
  @spec send_log(atom, any, String.t(), [atom]) :: :ok
  def send_log(level, message, time, tags \\ []) do
    Membrane.Log.Router |> send({:membrane_log, level, message, time, tags})
    :ok
  end

  @doc """
  Converts atom with level to its number representation

  Valid atoms are:
   - :debug
   - :info
   - :warn
  """
  @spec level_to_val(Membrane.Log.level_t()) :: 0 | 1 | 2
  def level_to_val(:debug), do: 0
  def level_to_val(:info), do: 1
  def level_to_val(:warn), do: 2

  # PRIVATE API

  @impl true
  def init(loggers) do
    loggers =
      loggers
      |> Enum.into(%{}, fn %{id: id} = logger_map ->
        level = logger_map |> Map.get(:level, :debug)
        tags = logger_map |> Map.get(:tags, [:all]) |> MapSet.new()
        {id, %{level: level, tags: tags}}
      end)

    {:ok, %{loggers: loggers}}
  end

  # Forwards log to every logger that has low enough level and has at least one
  # common tag with the message
  @impl true
  def handle_info(
        {:membrane_log, log_level, _message, _time, tags} = log,
        %{loggers: loggers} = state
      ) do
    Supervisor.each_logger(fn {id, pid, _type, _module} ->
      logger = loggers |> Map.get(id)

      if logger |> accepts_level?(log_level) and logger |> accepts_any_tag?(tags) do
        send(pid, log)
      end
    end)

    {:noreply, state}
  end

  defp accepts_level?(%{level: logger_lvl}, lvl) do
    level_to_val(logger_lvl) <= level_to_val(lvl)
  end

  defp accepts_any_tag?(%{tags: logger_tags}, tags) do
    tags = MapSet.new([:all | tags])
    not MapSet.disjoint?(logger_tags, tags)
  end
end
