defmodule Membrane.Core.Observability do
  @moduledoc false

  alias Membrane.ComponentPath

  @unsafely_name_processes_for_observer Application.compile_env(
                                          :membrane_core,
                                          :unsafely_name_processes_for_observer,
                                          []
                                        )

  @type config :: %{
          optional(:parent_path) => ComponentPath.path_t(),
          optional(:log_metadata) => Logger.metadata(),
          name: term,
          component_type: :element | :bin | :pipeline,
          pid: pid()
        }

  @spec setup(config, utility_name :: String.Chars.t()) :: :ok
  def setup(config, utility_name \\ "") do
    %{name: name, component_type: component_type, pid: pid} = config
    utility_name = if utility_name == "", do: "", else: " #{utility_name}"
    parent_path = Map.get(config, :parent_path, [])
    log_metadata = Map.get(config, :log_metadata, [])
    Logger.metadata(log_metadata)

    {name, unique_prefix, component_type_suffix} =
      if name,
        do: {name, "#{:erlang.pid_to_list(pid)} ", ""},
        else: {"#{:erlang.pid_to_list(pid)}", "", " (#{component_type})"}

    name_suffix = if component_type == :element, do: "", else: "/"
    name_str = if(String.valid?(name), do: name, else: inspect(name)) <> name_suffix

    register_name_for_observer(
      :"##{unique_prefix}#{name_str}#{component_type_suffix}#{utility_name}"
    )

    ComponentPath.set_and_append(parent_path, name_str)
    Membrane.Logger.set_prefix(ComponentPath.get_formatted() <> utility_name)
    :ok
  end

  if :components in @unsafely_name_processes_for_observer do
    defp register_name_for_observer(name) do
      if Process.info(self(), :registered_name) == {:registered_name, []} do
        Process.register(self(), name)
      end

      :ok
    end
  else
    defp register_name_for_observer(_name), do: :ok
  end

  @spec setup_link(Membrane.Pad.ref_t(), metadata) :: metadata
        when metadata: %{optional(:process_to_link) => pid()}
  if :links in @unsafely_name_processes_for_observer do
    def setup_link(pad_ref, observability_metadata \\ %{}) do
      {:ok, observer_dbg_process} =
        Task.start_link(fn ->
          Process.flag(:trap_exit, true)
          Process.register(self(), :"pad #{inspect(pad_ref)} #{:erlang.pid_to_list(self())}")
          process_to_link = Map.get(observability_metadata, :process_to_link)
          if process_to_link, do: Process.link(process_to_link)

          receive do
            {:EXIT, _pid, _reason} -> :ok
          end
        end)

      %{process_to_link: observer_dbg_process}
    end
  else
    def setup_link(_pad_ref, _observability_metadata \\ %{}), do: %{}
  end
end
