defmodule Membrane.Core.Telemetry do
  @moduledoc false
  # This module provides a way to gather datapoints and spans from running Membrane components, as well
  # as exposing these events in a format idiomatic to [Telemetry](https://hexdocs.pm/telemetry/)
  # library. It uses compile time flags from `config.exs` to determine which events should be
  # collected and propagated. This avoids unnecessary runtime overhead when telemetry is not needed.

  alias Membrane.Core.CallbackHandler
  alias Membrane.Core.Parent.Link

  alias Membrane.ComponentPath
  alias Membrane.Element
  alias Membrane.Element.WithInputPads
  alias Membrane.Element.WithOutputPads
  alias Membrane.Pad
  alias Membrane.Telemetry

  require Membrane.Bin, as: Bin
  require Membrane.Element.Base, as: ElementBase
  require Membrane.Element.WithOutputPads
  require Membrane.Element.WithInputPads
  require Membrane.Pipeline, as: Pipeline
  require Logger

  require Membrane.Core.LegacyTelemetry, as: LegacyTelemetry

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

  # Handles telemetry datapoints that were measured before but differ in how they were emitted
  # It's public to avoid dialyzer warnings. Not intended for external use
  @spec do_legacy_telemetry(atom(), Macro.t()) :: Macro.t()
  def do_legacy_telemetry(:link, lazy_block) do
    quote do
      LegacyTelemetry.report_link(unquote(lazy_block)[:from], unquote(lazy_block)[:to])
    end
  end

  def do_legacy_telemetry(metric_name, lazy_block) do
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
        for callback <- callbacks_list do
          if callback not in @possible_callbacks[component] do
            raise """
              Invalid telemetry flag: #{inspect(callback)}.
              Possible values for #{component} are: #{inspect(@possible_callbacks[component])}
            """
          end

          def handler_reported?(unquote(component), unquote(callback)), do: true
        end
    end
  end

  def handler_reported?(_component, _callback), do: false

  @spec datapoint_gathered?(any()) :: false | nil | true
  def datapoint_gathered?(datapoint) do
    datapoints = @config[:datapoints]
    datapoints && (datapoints == :all || datapoint in datapoints)
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

  defmacrop report_datapoint(datapoint_name, do: lazy_block) do
    unless Macro.quoted_literal?(datapoint_name), do: raise("Datapoint type must be a literal")

    cond do
      @legacy? ->
        do_legacy_telemetry(datapoint_name, lazy_block)

      datapoint_gathered?(datapoint_name) ->
        quote do
          value = unquote(lazy_block)

          :telemetry.execute(
            [:membrane, :datapoint, unquote(datapoint_name)],
            %{value: value},
            %{
              datapoint: unquote(datapoint_name),
              component_path: ComponentPath.get(),
              component_metadata: Logger.metadata()
            }
          )
        end

      true ->
        quote do
          _fn = fn ->
            _unused = unquote(datapoint_name)
            _unused = unquote(lazy_block)
          end

          :ok
        end
    end
  end

  @doc """
  Reports a span of a compoment callback function in a format consistent with `span/3` in `:telementry`
  """
  @spec track_callback_handler(
          (-> CallbackHandler.callback_return() | no_return()),
          module(),
          atom(),
          Telemetry.callback_span_metadata()
        ) :: CallbackHandler.callback_return() | no_return()
  def track_callback_handler(f, component_module, callback, meta) do
    component_type = state_module_to_atom(component_module)

    if handler_reported?(component_type, callback) do
      :telemetry.span([:membrane, component_type, callback], meta, fn ->
        {_actions, int_state} = res = f.()

        # Append the internal state returned from the callback to the metadata
        {res, %{meta | state_after_callback: int_state}}
      end)
    else
      f.()
    end
  end

  @doc """
  Formats metadata for a span of a component callback function
  """
  @spec callback_meta(
          Element.state() | Bin.state() | Pipeline.state(),
          atom(),
          [any()],
          Telemetry.callback_context()
        ) :: Telemetry.callback_span_metadata()
  def callback_meta(state, callback, args, context) do
    %{
      callback: callback,
      callback_args: args,
      callback_context: context,
      component_path: ComponentPath.get(),
      component_type: state.module,
      state_before_callback: state.internal_state,
      state_after_callback: nil
    }
  end

  @spec report_incoming_event(%{pad_ref: String.t()}) :: :ok
  def report_incoming_event(meta), do: report_datapoint(:event, do: meta)

  @spec report_stream_format(Membrane.StreamFormat.t(), String.t()) :: :ok
  def report_stream_format(format, pad_ref),
    do: report_datapoint(:stream_format, do: %{format: format, pad_ref: pad_ref})

  @spec report_buffer(integer() | list()) :: :ok
  def report_buffer(length)

  def report_buffer(length) when is_integer(length),
    do: report_datapoint(:buffer, do: length)

  def report_buffer(buffers) do
    report_datapoint(:buffer, do: length(buffers))
  end

  @spec report_store(integer(), String.t()) :: :ok
  def report_store(size, log_tag) do
    report_datapoint :store do
      %{size: size, log_tag: log_tag}
    end
  end

  @spec report_take(integer(), String.t()) :: :ok
  def report_take(size, log_tag) do
    report_datapoint :take do
      %{size: size, log_tag: log_tag}
    end
  end

  @spec report_queue_len(pid()) :: :ok
  def report_queue_len(pid) do
    report_datapoint :queue_len do
      {:message_queue_len, len} = Process.info(pid, :message_queue_len)
      %{len: len}
    end
  end

  @spec report_link(Link.Endpoint.t(), Link.Endpoint.t()) :: :ok
  def report_link(from, to) do
    report_datapoint :link do
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
