defmodule Membrane.Logger.Router do
  use GenServer

  alias Membrane.Logger.Supervisor


  @doc """
  Starts router as a separate process.

  Options are passed to `Supervisor.start_link/3`.
  """
  @spec start_link(any, GenServer.options) :: GenServer.on_start
  def start_link(loggers, process_options \\ []) do
    GenServer.start_link(__MODULE__, loggers, process_options)
  end


  @doc """
  Sends asynchronous call to the router, requesting it to forward log message
  to appropriate loggers.

  This functions assumes that passed log has level equal or greater than global
  level.
  """
  @spec send_log(atom, any, Membane.Time.native_t, atom) :: :ok
  def send_log(level, message, timestamp, tags \\ []) do
    :membrane_log_router |> GenServer.cast({:membrane_log, level, message, timestamp, tags})
    :ok
  end



  # PRIVATE API

  @doc false
  def init(loggers) do
    loggers = loggers |> Enum.map(
      fn %{id: id} = logger_map ->
        level = logger_map |> Map.get(:level, :debug)
        tags = logger_map |> Map.get(:tags, [:all]) |>  MapSet.new
        {id, %{level: level, tags: tags}}
      end) |> Enum.into(%{})

    {:ok, %{loggers: loggers}}
  end


  # Forwards log to every logger that has high enough level and has at least one
  # common tag with the message
  @doc false
  def handle_cast({:membrane_log, log_level, _message, _timestamp, tags} = log, %{loggers: loggers} = state) do
      fn {id, pid, _type, _module} ->
        logger = loggers |> Map.get(id)
        if (logger.level |> level_to_val) <= (log_level |> level_to_val) do
          tags = MapSet.new(tags ++ [:all])
          if logger.tags |> MapSet.intersection(tags) |> Enum.empty? |> Kernel.not do
            send pid, log
          end
        end
      end |> Supervisor.each_logger

      {:noreply, state}
  end



  defp level_to_val(:debug), do: 0
  defp level_to_val(:info), do: 1
  defp level_to_val(:warn), do: 2
  defp level_to_val(:critical), do: 3
end
