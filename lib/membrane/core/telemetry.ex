defmodule Membrane.Core.Telemetry do
  @moduledoc false
  # This module provides a way to gather metrics from running Membrane components, as well
  # as exposing these metrics in a format idiomatic to [Telemetry](https://hexdocs.pm/telemetry/)
  # library. It uses compile time flags from `config.exs` to determine which metrics should be
  # collected and propagated. This avoids unnecessary runtime overhead when telemetry is not needed.

  require Logger
  alias Membrane.ComponentPath


  # TODO find a proper way to describe types of measured metrics
  @possible_flags [:init, :terminate_request, :setup, :playing, :link, :parent_notification]
  @telemetry_flags Application.compile_env(:membrane_core, :telemetry_flags, [])

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

  defmacro report_metric(_, _), do: nil

  defmacro report_metric(_, _, _), do: nil

  @doc """
  Sanitizes state data by removing keys that are meant to be internal-only.
  """
  @spec sanitize_state_data(struct()) :: map()
  def sanitize_state_data(state = %struct{}) do
    Map.take(state, @public_state_keys[struct])
  end

  defp get_public_pad_name(pad) do
    quote bind_quoted: [pad: pad] do
      case pad.pad_ref do
        {:private, direction} -> direction
        {Membrane.Pad, {:private, direction}, ref} -> {Membrane.Pad, direction, ref}
        _pad -> pad.pad_ref
      end
    end
  end

  @doc """
  Reports new link connection being initialized in pipeline.
  """
  @spec report_link(Membrane.Pad.ref(), Membrane.Pad.ref()) :: Macro.t()
  defmacro report_link(from, to) do
    event = [:membrane, :link, :new]

    value =
      quote do
        %{
          from: unquote(from),
          to: unquote(to),
          pad_from: unquote(get_public_pad_name(from)),
          pad_to: unquote(get_public_pad_name(to))
        }
      end

    report_event(:link, event, value)
  end

  @doc """
  Reports an arbitrary span consistent with span format in `:telementry`
  """
  @spec report_span(module(), binary(), fun()) :: any()
  def report_span(component_type, event_type, f) do
    component_type = state_module_to_atom(component_type)
    event_type = handler_to_event_name(event_type)

    if event_enabled?(event_type) do
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
                 old_internal_state: old_intstate,
                 old_state: sanitize_state_data(old_state),
                 new_internal_state: new_intstate,
                 log_metadata: Logger.metadata(),
                 path: ComponentPath.get()
               }}

            _other ->
              raise "Unexpected telemetry span result. Use Telemetry.result/3 macro"
          end
        end
      )
    else
      {:telemetry_result, {result, _, _, _}} = f.()
      result
    end
  end

  defp state_module_to_atom(Membrane.Core.Element.State), do: :element
  defp state_module_to_atom(Membrane.Core.Bin.State), do: :bin
  defp state_module_to_atom(Membrane.Core.Pipeline.State), do: :pipeline

  defp handler_to_event_name(a) when is_atom(a), do: handler_to_event_name(Atom.to_string(a))
  defp handler_to_event_name("handle_" <> r) when is_binary(r), do: String.to_atom(r)

  def state_result(res = {_actions, new_internal_state}, old_internal_state, old_state) do
    {:telemetry_result, {res, new_internal_state, old_internal_state, old_state}}
  end

  defp report_event(event_type, event_name, measurement, metadata \\ quote(do: %{})) do
    if event_enabled?(event_type) do
      quote do
        :telemetry.execute(
          unquote(event_name),
          unquote(measurement),
          %{
            log_metadata: Logger.metadata(),
            path: ComponentPath.get()
          }
          |> Map.merge(unquote(metadata))
        )
      end
    else
      :ok
    end
  end

  case @telemetry_flags do
    :all ->
      def event_enabled?(_), do: true

    exclude: _, include: _ ->
      raise """
        `config :membrane_core, :telemetry_flags` should contain either :all, [include:[]] or [exclude:[]]
      """

    include: _, exclude: _ ->
      raise """
        `config :membrane_core, :telemetry_flags` should contain either :all, [include:[]] or [exclude:[]]
      """

    include: inc ->
      for event <- inc do
        if event not in @possible_flags do
          raise """
            Invalid telemetry flag: #{inspect(event)}.
            Possible values are: #{inspect(@possible_flags)}
          """
        end

        def event_enabled?(unquote(event)), do: true
      end

      def event_enabled?(_), do: false

    exclude: exc ->
      for event <- exc do
        def event_enabled?(unquote(event)), do: false
      end

      def event_enabled?(_), do: true
  end
end
