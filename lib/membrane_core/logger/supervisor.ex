defmodule Membrane.Logger.Supervisor do
  @moduledoc """
  Module responsible for supervising all loggers. It is also responsible for
  receiving and routing log messages to appropriate loggers.

  It is spawned upon application boot.
  """

  use Supervisor
  import Supervisor.Spec

  @type child_id_t :: any  # TODO check this

  @doc """
  Starts the Supervisor.

  Options are passed to `Supervisor.start_link/3`.
  """
  @spec start_link(Supervisor.options) :: Supervisor.on_start
  def start_link(options \\ []) do
    Supervisor.start_link(__MODULE__, nil, options ++ [name: __MODULE__])
  end


  @spec log(atom, any, Membane.Time.native_t, atom) :: :ok
  def log(level, message, timestamp, tag) do
    fn {_, pid, _, _} ->
      send pid, {:membrane_log, level, message, timestamp, tag}
    end |> each_children
  end

  @doc """
  Initializes logger and adds it to the supervision tree.

  As argumets, it expects module name, logger options and process/logger id

  If successful returns :ok
  On error returns :invalid_module
  """
  @spec add_logger(atom, any, child_id_t) :: :ok | :invalid_module
  def add_logger(module, options, child_id) do
    child_spec = worker(Membrane.Logger, [module, options], [id: child_id])

    case Supervisor.start_child(__MODULE__, child_spec) do
      {:ok, _child} -> :ok
      _error -> :invalid_module
    end
  end



  @doc """
  Removes logger from the supervision tree

  If succesful returns :ok
  If logger could not be found returns :not_found
  On other atom errors pass this value
  on other errors return :unknown_error
  """
  @spec remove_logger(child_id_t) :: atom
  def remove_logger(child_id) do

    Supervisor.terminate_child(__MODULE__, child_id)
    case Supervisor.delete_child(__MODULE__, child_id) do
      :ok -> :ok
      {:error, :not_found} -> :not_found
      {:error, error} when is_atom(error) -> error
      _ -> :unknown_error
    end
  end


  # Private API

  @doc false
  def init(nil) do
    config = Application.get_env(:membrane_core, Membrane.Logger, [])
    loggers = config |> Keyword.get(:loggers, [])

    child_list = loggers |> Enum.map(fn logger_map ->
        %{module: module, id: child_id} = logger_map
        options = logger_map |> Map.get(:options)

        # TODO do something with :level

        worker(Membrane.Logger, [module, options], [id: child_id])
    end)

    supervise(child_list, strategy: :one_for_one)
  end


  defp each_children(func) do
    __MODULE__ |> Supervisor.which_children |> Enum.each(func)
  end

end
