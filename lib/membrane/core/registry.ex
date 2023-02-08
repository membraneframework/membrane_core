defmodule Membrane.Core.Registry do
  @moduledoc false

  @registry_name MembraneComponentsRegistry

  @spec get_registry_name() :: module()
  def get_registry_name(), do: @registry_name

  @spec register_pipeline_descendant(pid()) :: :ok
  def register_pipeline_descendant(pipeline_pid) do
    get_registry_name()
    |> Registry.register(pipeline_pid, :component)

    :ok
  end

  @spec monitor_pipeline_descendants(pid) :: [reference()]
  def monitor_pipeline_descendants(pipeline_pid) do
    get_registry_name()
    |> Registry.lookup(pipeline_pid)
    |> Enum.map(fn {component_pid, :component} ->
      Process.monitor(component_pid)
    end)
  end

  @spec kill_pipeline_descendants(pid) :: :ok
  def kill_pipeline_descendants(pipeline_pid) do
    get_registry_name()
    |> Registry.dispatch(pipeline_pid, fn entries ->
      for {component_pid, :component} <- entries do
        Process.exit(component_pid, :kill)
      end
    end)
  end
end
