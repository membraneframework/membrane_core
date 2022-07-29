defmodule Membrane.Core.Observability do
  @unsafely_name_processes_for_observer Application.compile_env(
                                          :membrane_core,
                                          :unsafely_name_processes_for_observer,
                                          []
                                        )

  def setup_fun(component_type, name, log_metadata \\ []) do
    component_path = Membrane.ComponentPath.get()

    fn args ->
      Logger.metadata(log_metadata)
      pid = Keyword.fetch!(args, :pid)

      utility_name =
        case Keyword.fetch(args, :utility) do
          {:ok, utility_name} -> " #{utility_name}"
          :error -> ""
        end

      {name, unique_prefix, component_type_suffix} =
        if name,
          do: {name, "#{:erlang.pid_to_list(pid)} ", ""},
          else: {"#{:erlang.pid_to_list(pid)}", "", " (#{component_type})"}

      name_suffix = if component_type == :element, do: "", else: "/"
      name_str = if(String.valid?(name), do: name, else: inspect(name)) <> name_suffix

      register_name_for_observer(
        :"##{unique_prefix}#{name_str}#{component_type_suffix}#{utility_name}"
      )

      Membrane.ComponentPath.set_and_append(component_path, name_str)
      Membrane.Logger.set_prefix(Membrane.ComponentPath.get_formatted() <> utility_name)
      log_metadata
    end
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
    def setup_link(_pad_ref, _observability_metadata \\ nil), do: %{}
  end
end
