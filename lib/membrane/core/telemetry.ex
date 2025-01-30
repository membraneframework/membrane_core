defmodule Membrane.Core.Telemetry do
  @moduledoc false
  # This module provides a way to gather events from running Membrane components, as well
  # as exposing these events in a format idiomatic to [Telemetry](https://hexdocs.pm/telemetry/)
  # library. It uses compile time flags from `config.exs` to determine which events should be
  # collected and propagated. This avoids unnecessary runtime overhead when telemetry is not needed.

  alias Membrane.ComponentPath
  alias Membrane.Element.WithInputPads
  alias Membrane.Element.WithOutputPads
  alias Membrane.Pad

  require Membrane.Logger

  require Membrane.Bin, as: Bin
  require Membrane.Element.Base, as: ElementBase
  require Membrane.Element.WithOutputPads
  require Membrane.Element.WithInputPads
  require Membrane.Pipeline, as: Pipeline

  require Membrane.Core.LegacyTelemetry, as: LegacyTelemetry

  @type telemetry_callback_result() ::
          {:telemetry_result,
           {
             result :: any(),
             arguments :: list(),
             new_internal_state :: map(),
             old_internal_state :: map(),
             context :: Membrane.Telemetry.callback_event_metadata()
           }}

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

  _callbacks = @possible_callbacks

  @config Application.compile_env(:membrane_core, :telemetry_flags, [])
  @legacy? Enum.any?(@config, &is_atom(&1)) || Keyword.has_key?(@config, :metrics)

  if @legacy? do
    Logger.warning("""
      Legacy telemetry is deprecated and will be removed in the next major release.
      Please update your configuration to use the new telemetry system.
    """)
  end

  @spec legacy?() :: boolean()
  def legacy?(), do: @legacy?

  # Handles telemetry events that were measured before but differ in how they were emitted
  defp do_legacy_telemetry(:link, lazy_block) do
    quote do
      LegacyTelemetry.report_link(unquote(lazy_block)[:from], unquote(lazy_block)[:to])
    end
  end

  defp do_legacy_telemetry(metric_name, lazy_block) do
    LegacyTelemetry.report_metric(metric_name, lazy_block)
  end

  @spec handler_reported?(atom(), atom()) :: boolean()
  for {component, callbacks} <- @config[:tracked_callbacks] || [] do
    case callbacks do
      :all ->
        def handler_reported?(unquote(component), _callback), do: true

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

  def handler_reported?(_component, _callback), do: false

  @spec event_gathered?(any()) :: false | nil | true
  def event_gathered?(event) do
    events = @config[:events]
    events && (events == :all || event in events)
  end

  @spec tracked_callbacks_available() :: [
          pipeline: [atom()],
          bin: [atom()],
          element: [atom()]
        ]
  def tracked_callbacks_available do
    @possible_callbacks
  end

  @spec tracked_callbacks() :: [
          pipeline: [atom()],
          bin: [atom()],
          element: [atom()]
        ]
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

  defmacrop report_event(event_name, do: lazy_block) do
    unless Macro.quoted_literal?(event_name), do: raise("Event type must be a literal")

    cond do
      @legacy? ->
        do_legacy_telemetry(event_name, lazy_block)

      event_gathered?(event_name) ->
        quote do
          value = unquote(lazy_block)

          :telemetry.execute(
            [:membrane, :event, unquote(event_name)],
            %{value: value},
            %{
              event: unquote(event_name),
              component_path: ComponentPath.get(),
              component_metadata: Logger.metadata()
            }
          )
        end

      true ->
        quote do
          _fn = fn ->
            _unused = unquote(event_name)
            _unused = unquote(lazy_block)
          end

          :ok
        end
    end
  end

  @doc """
  Reports an arbitrary span of a function consistent with `span/3` format in `:telementry`
  """
  @spec component_span(module(), atom(), (-> telemetry_callback_result())) :: any()
  def component_span(component_type, callback, f) do
    component_type = state_module_to_atom(component_type)

    if handler_reported?(component_type, callback) do
      :telemetry.span(
        [:membrane, component_type, callback],
        %{
          component_path: ComponentPath.get(),
          callback: callback,
          component_type: component_type
        },
        fn -> unpack_state_result(f, callback, component_type) end
      )
    else
      {:telemetry_result, {result, _args, _new_intstate, _old_intstate, _old_state}} = f.()
      result
    end
  end

  defp unpack_state_result(fun, callback, component_type) do
    case fun.() do
      {:telemetry_result, {r, args, new_intstate, old_intstate, old_state}} ->
        {r, %{},
         %{
           callback_args: args,
           component_path: ComponentPath.get(),
           callback: callback,
           component_metadata: %{
             component_type: component_type,
             component_context: old_state,
             component_module: old_state.module,
             internal_state_before: old_intstate,
             internal_state_after: new_intstate
           }
         }}

      _other ->
        raise "Unexpected telemetry span result. Use Telemetry.state_result/3 instead"
    end
  end

  @doc """
  Formats a telemetry result to be used in a report_span function.
  """
  @spec state_result(any(), list(), internal_state, internal_state, map()) ::
          telemetry_callback_result()
        when internal_state: any()
  def state_result(res, args, old_internal_state, new_internal_state, old_state) do
    {:telemetry_result, {res, args, new_internal_state, old_internal_state, old_state}}
  end

  @spec report_incoming_event(%{pad_ref: String.t()}) :: :ok
  def report_incoming_event(meta), do: report_event(:event, do: meta)

  @spec report_stream_format(Membrane.StreamFormat.t(), String.t()) :: :ok
  def report_stream_format(format, pad_ref),
    do: report_event(:stream_format, do: %{format: format, pad_ref: pad_ref})

  @spec report_buffer(integer() | list()) :: :ok
  def report_buffer(length)

  def report_buffer(length) when is_integer(length),
    do: report_event(:buffer, do: length)

  def report_buffer(buffers) do
    report_event(:buffer, do: length(buffers))
  end

  @spec report_store(integer(), String.t()) :: :ok
  def report_store(size, log_tag) do
    report_event :store do
      %{size: size, log_tag: log_tag}
    end
  end

  @spec report_take(integer(), String.t()) :: :ok
  def report_take(size, log_tag) do
    report_event :take do
      %{size: size, log_tag: log_tag}
    end
  end

  @spec report_queue_len(pid()) :: :ok
  def report_queue_len(pid) do
    report_event :queue_len do
      {:message_queue_len, len} = Process.info(pid, :message_queue_len)
      %{len: len}
    end
  end

  @spec report_link(Membrane.Pad.ref(), Membrane.Pad.ref()) :: :ok
  def report_link(from, to) do
    report_event :link do
      %{
        parent_component_path: ComponentPath.get_formatted(),
        from: inspect(from.child),
        to: inspect(to.child),
        pad_from: Pad.name_by_ref(from.pad_ref) |> inspect(),
        pad_to: Pad.name_by_ref(to.pad_ref) |> inspect()
      }
    end
  end

  defp state_module_to_atom(Membrane.Core.Element.State), do: :element
  defp state_module_to_atom(Membrane.Core.Bin.State), do: :bin
  defp state_module_to_atom(Membrane.Core.Pipeline.State), do: :pipeline
end
