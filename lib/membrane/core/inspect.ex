defmodule Membrane.Core.Inspect do
  @moduledoc false

  alias Inspect.Algebra
  alias Membrane.Core.Component

  @fields_order [
    :module,
    :name,
    :pid,
    :parent_pid,
    :playback,
    :type,
    :internal_state,
    :pads_info,
    :pads_data,
    :children,
    :links,
    :crash_groups,
    :pending_specs,
    :synchronization,
    :delayed_demands,
    :effective_flow_control,
    :initialized?,
    :terminating?,
    :setup_incomplete?,
    :supplying_demand?,
    :handling_action?,
    :stalker,
    :resource_guard,
    :subprocess_supervisor,
    :children_log_metadata,
    :handle_demand_loop_counter,
    :demand_size,
    :playback_queue,
    :pads_to_snapshot
  ]

  @spec inspect(Component.state(), Inspect.Opts.t()) :: Inspect.Algebra.t()
  def inspect(state, opts) do
    field_doc_extractor =
      fn field, opts ->
        case Map.fetch(state, field) do
          {:ok, value} ->
            value_doc = Algebra.to_doc(value, opts)
            Algebra.concat("#{Atom.to_string(field)}: ", value_doc)

          :error ->
            Algebra.empty()
        end
      end

    Algebra.container_doc(
      "%#{Kernel.inspect(state.__struct__)}{",
      @fields_order,
      "}",
      opts,
      field_doc_extractor,
      break: :strict
    )
  end

  @spec ensure_all_struct_fields_inspected!(module()) :: :ok | no_return()
  def ensure_all_struct_fields_inspected!(state_module) do
    state_module.__info__(:struct)
    |> Enum.map(& &1.field)
    |> Enum.filter(&(&1 not in @fields_order))
    |> case do
      [] ->
        :ok

      fields ->
        raise """
        Fields #{inspect(fields)} from #{inspect(state_module)} structure are omitted in @fields_order module attribute in #{inspect(__MODULE__)}. Add them to @fields_order, to define where they will occur in the error logs.
        """
    end
  end
end

[Pipeline, Bin, Element]
|> Enum.map(fn component ->
  state_module = Module.concat([Membrane.Core, component, State])

  :ok = Membrane.Core.Inspect.ensure_all_struct_fields_inspected!(state_module)

  defimpl Inspect, for: state_module do
    @spec inspect(unquote(state_module).t(), Inspect.Opts.t()) :: Inspect.Algebra.t()
    defdelegate inspect(state, opts), to: Membrane.Core.Inspect
  end
end)
