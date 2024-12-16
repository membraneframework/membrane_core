defmodule Membrane.Core.Telemetry do
  @moduledoc false
  # This module provides a way to gather metrics from running Membrane components, as well
  # as exposing these metrics in a format idiomatic to [Telemetry](https://hexdocs.pm/telemetry/)
  # library. It uses compile time flags from `config.exs` to determine which metrics should be
  # collected and propagated. This avoids unnecessary runtime overhead when telemetry is not needed.

  require Logger
  alias Membrane.ComponentPath

  @possible_flags [:init, :terminate, :setup, :playing, :link]
  @telemetry_flags Application.compile_env(:membrane_core, :telemetry_flags, [])
  @invalid_config_warning """
    `config :membrane_core, :telemetry_flags` should contain either :all, [include:[]] or [exclude:[]]"
  """

  @public_state_keys %{
    Membrane.Core.Element.State => [
      :type,
      :name,
      :pads_info,
      :initialized?
    ]
  }

  # Verify at compile time that every key is actually present in Core.Element.State
  for {mod, keys} <- @public_state_keys do
    case keys -- Map.keys(struct(mod)) do
      [] ->
        :ok

      other ->
        raise "Public telemetry keys #{inspect(other)} absent in #{mod}"
    end
  end

  @doc """
  Reports a metric with its coresponding value. E.g. input buffers size or received stream format.
  """
  @spec report_metric(atom(), any(), map()) :: Macro.t()
  defmacro report_metric(metric, value, meta \\ %{}) do
    event =
      [:membrane, :metric, :value]

    value =
      Macro.escape(%{
        component_path: ComponentPath.get(),
        metric: Atom.to_string(metric),
        value: value,
        meta: meta
      })

    report_event(:metrics, event, value)
  end

  @doc """
  Given a list of buffers calculates total size of their payloads in bits
  and reports it.
  """
  @spec report_bitrate([Membrane.Buffer.t()]) :: Macro.t()
  defmacro report_bitrate(buffers) do
    event = [:membrane, :metric, :value]

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

    report_event(:bitrate, event, value)
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
  @spec report_link(Membrane.Pad.t(), Membrane.Pad.t()) :: Macro.t()
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

  defmacro report_playing(component_type) do
    report_event(:playing, [:membrane, component_type, :playing], quote(do: %{}))
  end

  @doc """
  Reports an arbitrary span consistent with span format in `:telementry`
  """
  @spec report_span(atom(), atom(), do: block) :: block when block: Macro.t()
  defmacro report_span(component_type, event_type, do: block) do
    if event_enabled?(event_type) do
      quote do
        :telemetry.span(
          [:membrane, unquote(component_type), unquote(event_type)],
          %{
            log_metadata: Logger.metadata(),
            path: ComponentPath.get()
          },
          fn ->
            {unquote(block), %{log_metadata: Logger.metadata(), path: ComponentPath.get()}}
          end
        )
      end
    else
      block
    end
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
