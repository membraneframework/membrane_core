defmodule Membrane.Core.Telemetry do
  @moduledoc false
  # This module provides a way to gather metrics from running Membrane components, as well
  # as exposing these metrics in a format idiomatic to [Telemetry](https://hexdocs.pm/telemetry/)
  # library. It uses compile time flags from `config.exs` to determine which metrics should be
  # collected and propagated. This avoids unnecessary runtime overhead when telemetry is not needed.

  require Logger
  require Membrane.Element.Base, as: ElementBase
  require Membrane.Element.WithOutputPads
  require Membrane.Element.WithInputPads
  require Membrane.Pipeline, as: Pipeline
  require Membrane.Bin, as: Bin

  alias Membrane.Element.WithOutputPads
  alias Membrane.Element.WithInputPads
  alias Membrane.ComponentPath

  @type telemetry_result() :: {:telemetry_result, {any(), map(), map(), map()}}

  @component_modules [
    bin: [Bin],
    pipeline: [Pipeline],
    element: [ElementBase, WithInputPads, WithOutputPads]
  ]

  @possible_handlers (for {elem, mods} <- @component_modules do
                        mods
                        |> Enum.flat_map(& &1.behaviour_info(:callbacks))
                        |> Enum.map(&elem(&1, 0))
                        |> Enum.filter(&String.starts_with?(to_string(&1), "handle_"))
                        |> then(&{elem, &1})
                      end)

  _ = @possible_handlers

  @config Application.compile_env(:membrane_core, :telemetry_flags, [])

  @public_state_keys %{
    Membrane.Core.Element.State => [
      :subprocess_supervisor,
      :terminating?,
      :setup_incomplete?,
      :effective_flow_control,
      :resource_guard,
      :initialized?,
      :playback,
      :module,
      :type,
      :name,
      :internal_state,
      :pads_info,
      :pads_data,
      :parent_pid
    ],
    Membrane.Core.Bin.State => [
      :internal_state,
      :module,
      :children,
      :subprocess_supervisor,
      :name,
      :pads_info,
      :pads_data,
      :parent_pid,
      :links,
      :crash_groups,
      :children_log_metadata,
      :playback,
      :initialized?,
      :terminating?,
      :resource_guard,
      :setup_incomplete?
    ],
    Membrane.Core.Pipeline.State => [
      :module,
      :playback,
      :internal_state,
      :children,
      :links,
      :crash_groups,
      :initialized?,
      :terminating?,
      :resource_guard,
      :setup_incomplete?,
      :subprocess_supervisor
    ]
  }

  # Verify at compile time that every key is actually present in Core.*.State
  for {mod, keys} <- @public_state_keys do
    case keys -- Map.keys(struct(mod)) do
      [] ->
        :ok

      other ->
        raise "Public telemetry keys #{inspect(other)} absent in #{mod}"
    end
  end

  for {component, handlers} <- @config[:tracked_callbacks] || [] do
    case handlers do
      :all ->
        def handler_measured?(unquote(component), _), do: true

      nil ->
        def handler_measured?(unquote(component), _), do: false

      handler_names when is_list(handler_names) ->
        for event <- handler_names do
          if event not in @possible_handlers[component] do
            raise """
              Invalid telemetry flag: #{inspect(event)}.
              Possible values for #{component} are: #{inspect(@possible_handlers[component])}
            """
          end

          def handler_measured?(unquote(component), unquote(event)), do: true
        end
    end
  end

  def handler_measured?(_, _), do: false

  case @config[:metrics] do
    :all ->
      def metric_measured?(_metric), do: true

    nil ->
      def metric_measured?(_metric), do: false

    list when is_list(list) ->
      for metric <- list do
        def metric_measured?(unquote(metric)), do: true
      end

      def metric_measured?(_metric), do: false
  end

  @doc """
  Formats a telemetry result to be used in a report_span function.
  """
  @spec state_result(result, {any(), map()}, map()) ::
          telemetry_result()
        when result: any()
  def state_result(res = {_actions, new_internal_state}, old_internal_state, old_state) do
    {:telemetry_result, {res, new_internal_state, old_internal_state, old_state}}
  end

  @doc """
  Reports an arbitrary span of a function consistent with `span/3` format in `:telementry`
  """
  @spec report_span(module(), atom(), (-> telemetry_result())) :: any()
  def report_span(component_type, event_type, f) do
    component_type = state_module_to_atom(component_type)

    if handler_measured?(component_type, event_type) do
      :telemetry.span(
        [:membrane, component_type, event_type],
        %{
          log_metadata: Logger.metadata(),
          path: ComponentPath.get()
        },
        fn ->
          case f.() do
            {:telemetry_result, {r, new_intstate, old_intstate, old_state}} ->
              {r, %{new_state: new_intstate},
               %{
                 internal_state_before: old_intstate,
                 state_before: sanitize_state_data(old_state),
                 internal_state_after: new_intstate,
                 log_metadata: Logger.metadata(),
                 path: ComponentPath.get()
               }}

            _other ->
              raise "Unexpected telemetry span result. Use Telemetry.state_result/3 instead"
          end
        end
      )
    else
      {:telemetry_result, {result, _, _, _}} = f.()
      result
    end
  end

  defp sanitize_state_data(state = %struct{}) do
    Map.take(state, @public_state_keys[struct])
  end

  defp state_module_to_atom(Membrane.Core.Element.State), do: :element
  defp state_module_to_atom(Membrane.Core.Bin.State), do: :bin
  defp state_module_to_atom(Membrane.Core.Pipeline.State), do: :pipeline

  def report_metric(metric_name, measurement, metadata \\ %{}) do
    if metric_measured?(metric_name) do
      :telemetry.execute([:membrane, :metric, metric_name], %{value: measurement}, metadata)
    else
      measurement
    end
  end
end
