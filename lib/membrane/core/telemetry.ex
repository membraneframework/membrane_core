defmodule Membrane.Core.Telemetry do
  @moduledoc false
  # This module provides a way to gather events from running Membrane components, as well
  # as exposing these events in a format idiomatic to [Telemetry](https://hexdocs.pm/telemetry/)
  # library. It uses compile time flags from `config.exs` to determine which events should be
  # collected and propagated. This avoids unnecessary runtime overhead when telemetry is not needed.

  require Logger
  require Membrane.Element.Base, as: ElementBase
  require Membrane.Element.WithOutputPads
  require Membrane.Element.WithInputPads
  require Membrane.Pipeline, as: Pipeline
  require Membrane.Bin, as: Bin

  alias Membrane.Pad
  alias Membrane.Element.WithOutputPads
  alias Membrane.Element.WithInputPads
  alias Membrane.ComponentPath

  require Membrane.Core.LegacyTelemetry, as: LegacyTelemetry

  @type telemetry_result() :: {:telemetry_result, {any(), map(), map(), map()}}

  @component_modules [
    bin: [Bin],
    pipeline: [Pipeline],
    element: [ElementBase, WithInputPads, WithOutputPads]
  ]

  @possible_callbacks (for {elem, mods} <- @component_modules do
                         mods
                         |> Enum.flat_map(& &1.behaviour_info(:callbacks))
                         |> Enum.map(&elem(&1, 0))
                         |> Enum.filter(&String.starts_with?(to_string(&1), "handle_"))
                         |> then(&{elem, &1})
                       end)

  _ = @possible_callbacks

  @config Application.compile_env(:membrane_core, :telemetry_flags, [])
  @legacy? Enum.any?(@config, &is_atom(&1)) || Keyword.has_key?(@config, :metrics)

  if @legacy? do
    Logger.warning("""
      Legacy telemetry is deprecated and will be removed in the next major release.
      Please update your configuration to use the new telemetry system.
    """)
  end

  def legacy?(), do: @legacy?

  # Functions below are telemetry events that were measured before but differ in how they were emitted
  defp do_legacy_telemetry(:link, _metadata, lazy_block) do
    LegacyTelemetry.report_link(
      quote(do: unquote(lazy_block)[:from]),
      quote(do: unquote(lazy_block)[:to])
    )
  end

  defp do_legacy_telemetry(metric_name, metadata, lazy_block) do
    LegacyTelemetry.report_metric(metric_name, lazy_block, quote(do: unquote(metadata)[:log_tag]))
  end

  for {component, callbacks} <- @config[:tracked_callbacks] || [] do
    case callbacks do
      :all ->
        def handler_reported?(unquote(component), _), do: true

      nil ->
        nil

      callbacks_list when is_list(callbacks_list) ->
        for event <- callbacks_list do
          if event not in @possible_callbacks[component] do
            raise """
              Invalid telemetry flag: #{inspect(event)}.
              Possible values for #{component} are: #{inspect(@possible_callbacks[component])}
            """
          end

          def handler_reported?(unquote(component), unquote(event)), do: true
        end
    end
  end

  def handler_reported?(_, _), do: false

  def event_gathered?(event) do
    events = @config[:events]
    events && (events == :all || event in events)
  end

  defmacrop report_event(event_name, metadata, do: lazy_block) do
    unless Macro.quoted_literal?(event_name), do: raise("Event type must be a literal")

    if @legacy? do
      do_legacy_telemetry(event_name, metadata, lazy_block)
    else
      if event_gathered?(event_name) do
        quote do
          value = unquote(lazy_block)

          :telemetry.execute(
            [:membrane, :event, unquote(event_name)],
            %{value: value},
            unquote(metadata)
          )
        end
      else
        quote do
          _fn = fn ->
            _unused = unquote(event_name)
            _unused = unquote(metadata)
            _unused = unquote(lazy_block)
          end
        end
      end
    end
  end

  def tracked_callbacks_available do
    @possible_callbacks
  end

  def tracked_callbacks do
    for {component, callbacks} <- @config[:tracked_callbacks] || [] do
      case callbacks do
        :all ->
          {component, @possible_callbacks[component]}

        nil ->
          {component, []}

        callbacks_list when is_list(callbacks_list) ->
          {component, callbacks_list}
      end
    end
  end

  @doc """
  Reports an arbitrary span of a function consistent with `span/3` format in `:telementry`
  """
  @spec component_span(module(), atom(), (-> telemetry_result())) :: any()
  def component_span(component_type, event_type, f) do
    component_type = state_module_to_atom(component_type)

    if handler_reported?(component_type, event_type) do
      :telemetry.span(
        [:membrane, component_type, event_type],
        %{
          event_metadata: Logger.metadata(),
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
                 event_metadata: Logger.metadata(),
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

  def report_incoming_event(meta \\ %{}), do: report_event(:event, meta, do: 1)

  def report_stream_format(format, meta \\ %{}),
    do: report_event(:stream_format, meta, do: format)

  def report_buffer(length, meta \\ %{})

  def report_buffer(length, meta) when is_integer(length),
    do: report_event(:buffer, meta, do: length)

  def report_buffer(buffers, meta) do
    report_event(:buffer, meta, do: length(buffers))
  end

  def report_store(size, log_tag) do
    report_event :store, %{log_tag: log_tag} do
      size
    end
  end

  def report_queue_len(pid, meta \\ %{}) do
    report_event :queue_len, meta do
      {:message_queue_len, len} = Process.info(pid, :message_queue_len)
      len
    end
  end

  def report_link(from, to) do
    report_event :link, %{
      parent_path: ComponentPath.get_formatted(),
      from: inspect(from.child),
      to: inspect(to.child),
      pad_from: Pad.name_by_ref(from.pad_ref) |> inspect(),
      pad_to: Pad.name_by_ref(to.pad_ref) |> inspect()
    } do
      %{from: from, to: to}
    end
  end

  defp state_module_to_atom(Membrane.Core.Element.State), do: :element
  defp state_module_to_atom(Membrane.Core.Bin.State), do: :bin
  defp state_module_to_atom(Membrane.Core.Pipeline.State), do: :pipeline
end
