defmodule Membrane.Log.Supervisor do
  @moduledoc deprecated: "Use Elixir `Logger` instead"
  @moduledoc """
  Module responsible for supervising router_level loggers. It is also responsible for
  receiving and routing log messages to appropriate loggers.

  It is spawned upon application boot.
  """

  use Supervisor

  @type child_id_t :: term

  @doc """
  Starts the Supervisor.

  Options are passed to `Supervisor.start_link/3`.
  """
  @spec start_link(Keyword.t(), [Supervisor.option()] | []) :: Supervisor.on_start()
  def start_link(config, options \\ []) do
    Supervisor.start_link(__MODULE__, config, options ++ [name: __MODULE__])
  end

  @doc """
  Initializes logger and adds it to the supervision tree.

  As arguments, it expects module name, logger options and process/logger id

  If successful returns :ok
  On error returns :invalid_module
  """
  @spec add_logger(atom, any, child_id_t) :: :ok | :invalid_module
  def add_logger(module, options, child_id) do
    child_spec = %{id: child_id, start: {Membrane.Log.Logger, :start_link, [module, options]}}

    case Supervisor.start_child(__MODULE__, child_spec) do
      {:ok, _child} -> :ok
      _error -> :invalid_module
    end
  end

  @doc """
  Removes logger from the supervision tree

  If successful returns :ok
  If logger could not be found, returns corresponding error
  """
  @spec remove_logger(child_id_t) :: atom
  def remove_logger(child_id) do
    Supervisor.terminate_child(__MODULE__, child_id)

    case Supervisor.delete_child(__MODULE__, child_id) do
      :ok -> :ok
      {:error, _err} = error -> error
    end
  end

  @doc """
  Iterates through list of children and executes given function on every
  child.

  Should return :ok.
  """
  @spec each_logger(([children_info] -> any())) :: :ok
        when children_info:
               {term() | :undefined, Supervisor.child() | :restarting, :worker | :supervisor,
                :supervisor.modules()}
  def each_logger(func) do
    __MODULE__ |> Supervisor.which_children() |> Enum.each(func)
    :ok
  end

  # Private API

  @impl true
  def init(config) do
    loggers = config |> Keyword.get(:loggers, [])

    child_list =
      loggers
      |> Enum.map(fn logger_map ->
        %{module: module, id: child_id} = logger_map
        options = logger_map |> Map.get(:options)

        %{id: child_id, start: {Membrane.Log.Logger, :start_link, [module, options]}}
      end)

    Supervisor.init(child_list, strategy: :one_for_one)
  end
end
