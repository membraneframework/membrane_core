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
  require Membrane.Telemetry

  alias Membrane.Pad
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

  for {component, handlers} <- @config[:tracked_callbacks] || [] do
    case handlers do
      :all ->
        def handler_measured?(unquote(component), _), do: true

      nil ->
        nil

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
  Reports an arbitrary span of a function consistent with `span/3` format in `:telementry`
  """
  @spec component_span(module(), atom(), (-> telemetry_result())) :: any()
  def component_span(component_type, event_type, f) do
    component_type = state_module_to_atom(component_type)

    if handler_measured?(component_type, event_type) do
      :telemetry.span(
        [:membrane, component_type, event_type],
        %{
          log_metadata: Logger.metadata(),
          path: ComponentPath.get(),
          component_path: ComponentPath.get_formatted()
        },
        fn ->
          case f.() do
            {:telemetry_result, {r, new_intstate, old_intstate, old_state}} ->
              {r, %{new_state: new_intstate},
               %{
                 internal_state_before: old_intstate,
                 state_before: old_state,
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

  @doc """
  Formats a telemetry result to be used in a report_span function.
  """
  @spec state_result(any(), internal_state, internal_state, map()) ::
          telemetry_result()
        when internal_state: any()
  def state_result(res, old_internal_state, new_internal_state, old_state) do
    {:telemetry_result, {res, new_internal_state, old_internal_state, old_state}}
  end

  def report_event(meta \\ %{}), do: report_metric(:event, 1, meta)
  def report_link(), do: report_metric(:link, 1)
  def report_store(size, log_tag), do: report_metric(:store, size, %{log_tag: log_tag})
  def report_stream_format(meta \\ %{}), do: report_metric(:stream_format, 1, meta)

  def report_buffer(length, meta \\ %{})

  def report_buffer(length, meta) when is_integer(length),
    do: report_metric(:buffer, length, meta)

  def report_buffer(buffers, meta) do
    if metric_measured?(:buffer) do
      value = length(List.wrap(buffers))
      report_buffer(value, meta)
    end
  end

  def report_bitrate(buffers, meta \\ %{}) do
    if metric_measured?(:bitrate) do
      value = Enum.reduce(List.wrap(buffers), 0, &(&2 + Membrane.Payload.size(&1.payload)))
      :telemetry.execute([:membrane, :metric, :bitrate], %{value: value}, meta)
    end
  end

  def report_link(from, to) do
    if metric_measured?(:link) do
      meta = %{
        parent_path: ComponentPath.get_formatted(),
        from: inspect(from.child),
        to: inspect(to.child),
        pad_from: Pad.name_by_ref(from.pad_ref) |> inspect(),
        pad_to: Pad.name_by_ref(to.pad_ref) |> inspect()
      }

      # For backwards compatibility
      :telemetry.execute([:membrane, :link, :new], %{from: from, to: to}, meta)
      :telemetry.execute([:membrane, :metric, :link], %{from: from, to: to}, meta)
    end
  end

  def report_metric(metric_name, measurement, metadata \\ %{}) do
    if metric_measured?(metric_name) do
      :telemetry.execute([:membrane, :metric, metric_name], %{value: measurement}, metadata)
    else
      measurement
    end
  end

  defp state_module_to_atom(Membrane.Core.Element.State), do: :element
  defp state_module_to_atom(Membrane.Core.Bin.State), do: :bin
  defp state_module_to_atom(Membrane.Core.Pipeline.State), do: :pipeline
end
