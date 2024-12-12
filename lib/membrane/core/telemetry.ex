defmodule Membrane.Core.Telemetry do
  @moduledoc false

  require Logger
  alias Membrane.ComponentPath

  require Membrane.Pad

  @possible_flags [:init, :terminate, :setup, :playing]
  @telemetry_flags Application.compile_env(:membrane_core, :telemetry_flags, [])
  @invalid_config_warning "`config :membrane_core, :telemetry_flags` should contain either :all, [include:[]] or [exclude:[]]"

  @doc """
  Reports metrics such as input buffer's size inside functions, incoming events and received stream format.
  """
  defmacro report_metric(metric, value, meta \\ quote(do: %{})) do
    event =
      [:membrane, :metric, :value]

    val =
      Macro.escape(%{
        component_path: ComponentPath.get(),
        metric: Atom.to_string(metric),
        value: value,
        meta: meta
      })

    report_event(
      event,
      val,
      Keyword.get(@telemetry_flags, :metrics, []) |> Enum.member?(metric)
    )
  end

  @doc """
  Given list of buffers (or a single buffer) calculates total size of their payloads in bits
  and reports it.
  """
  defmacro report_bitrate(buffers) do
    event =
      quote do
        [:membrane, :metric, :value]
      end

    value =
      quote do
        %{
          component_path: ComponentPath.get(),
          metric: "bitrate",
          value:
            8 *
              Enum.reduce(
                List.wrap(unquote(buffers)),
                0,
                &(Membrane.Payload.size(&1.payload) + &2)
              )
        }
      end

    report_event(
      event,
      value,
      Keyword.get(@telemetry_flags, :metrics, []) |> Enum.member?(:bitrate)
    )
  end

  @doc false
  @spec __get_public_pad_name__(Membrane.Pad.ref()) :: Membrane.Pad.ref()
  def __get_public_pad_name__(pad) do
    case pad do
      {:private, direction} -> direction
      {Membrane.Pad, {:private, direction}, ref} -> {Membrane.Pad, direction, ref}
      _pad -> pad
    end
  end

  @doc """
  Reports new link connection being initialized in pipeline.
  """
  defmacro report_link(from, to) do
    event =
      quote do
        [:membrane, :link, :new]
      end

    value =
      quote do
        %{
          parent_path: Membrane.ComponentPath.get_formatted(),
          from: inspect(unquote(from).child),
          to: inspect(unquote(to).child),
          pad_from:
            Membrane.Core.Telemetry.__get_public_pad_name__(unquote(from).pad_ref) |> inspect(),
          pad_to:
            Membrane.Core.Telemetry.__get_public_pad_name__(unquote(to).pad_ref) |> inspect()
        }
      end

    report_event(event, value, Enum.member?(@telemetry_flags, :links))
  end

  defmacro report_span(element_type, event_type, do: block) do
    if event_enabled?(event_type) do
      quote do
        :telemetry.span(
          [:membrane, unquote(element_type), unquote(event_type)],
          %{
            log_metadata: Logger.metadata(),
            path: ComponentPath.get()
          },
          fn ->
            unquote(block)
            |> then(&{&1, %{log_metadata: Logger.metadata(), path: ComponentPath.get()}})
          end
        )
      end
    else
      block
    end
  end

  # Conditional event reporting of telemetry events
  defp report_event(event_name, measurement, enabled, metadata \\ nil) do
    if enabled do
      quote do
        :telemetry.execute(
          unquote(event_name),
          unquote(measurement),
          unquote(metadata) || %{}
        )
      end
    else
      :ok
    end
  end

  defp event_enabled?(flag) do
    Enum.member?(get_flags(@telemetry_flags), flag)
  end

  defp get_flags(:all), do: @possible_flags
  defp get_flags(include: _, exclude: _), do: warn(@invalid_config_warning)
  defp get_flags(exclude: exclude), do: @possible_flags -- exclude

  defp get_flags(include: include) do
    case include -- @possible_flags do
      [] ->
        include

      incorrect_flags ->
        warn("#{inspect(incorrect_flags)} are not correct Membrane telemetry flags")
    end
  end

  defp get_flags(_), do: []

  defp warn(warning) do
    IO.warn(warning, Macro.Env.stacktrace(__ENV__))
  end
end
