defmodule Membrane.Telemetry do
  @moduledoc """
  Defines basic telemetry event types used by Membrane.Core that can be consumed by attaching to [Telemetry Package](https://hex.pm/packages/telemetry).

  It is user's responsibility to use some sort of metrics reporter
  that will be attached to mentioned library to consume and process generated metrics. Membrane.Core does not
  store any metrics by itself, just delegates it to Telemetry package.
  """

  @type event_name_t :: [atom(), ...]

  @type input_buffer_size_event_value_t :: %{
          element_path: String.t(),
          method: String.t(),
          value: integer()
        }

  @doc """
  Returns event name used by InputBuffer to report current buffer size inside of functions
  `Membrane.Core.InputBuffer.store/3` and
  `Membrane.Core.InputBuffer.take_and_demand/4`.
  Given event's metric value is of format: `t:input_buffer_size_event_value_t/0`
  """
  @spec input_buffer_size_event() :: event_name_t()
  def input_buffer_size_event, do: [:membrane, :input_buffer, :size]
end
