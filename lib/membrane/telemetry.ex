defmodule Membrane.Telemetry do
  @moduledoc """
  Defines basic telemetry event types used by Membrane's Core.
  Membrane uses [Telemetry Package](https://hex.pm/packages/telemetry) for instrumentation and does not store or save any measurements by itself.

  It is user's responsibility to use some sort of metrics reporter
  that will be attached to `:telemetry` package to consume and process generated measurements.

  ## Instrumentation
  `Membrane.Telemetry` publishes functions that return described below event names.

  The following events are published by Membrane's Core with following measurement types and metadata:

    * `[:membrane, :input_buffer, :size]` - to report current input buffer's size.
        * Measurement: `t:input_buffer_size_event_value_t/0`
        * Metadata: `%{}`

    * `[:membrane, :link, :new]` - to report new link connection being initialized in pipeline.
        * Measurement: `t:new_link_event_value_t/0`
        * Metadata: `%{}`

  """

  @type event_name_t :: [atom(), ...]

  @typedoc """
  * element_path - element's process path with pad's name that input buffer is attached to
  * method - input buffer's function call name
  * value - current buffer's size

  """
  @type input_buffer_size_event_value_t :: %{
          element_path: String.t(),
          method: String.t(),
          value: integer()
        }

  @spec input_buffer_size_event_name() :: event_name_t()
  def input_buffer_size_event_name, do: [:membrane, :input_buffer, :size]

  @typedoc """
  * parent_path - process path of link's parent
  * from - from element name
  * to - to element name
  * pad_from - from's pad name
  * pad_to - to's pad name
  """
  @type new_link_event_value_t :: %{
          parent_path: String.t(),
          from: String.t(),
          to: String.t(),
          pad_from: String.t(),
          pad_to: String.t()
        }

  @spec new_link_event_name() :: event_name_t()
  def new_link_event_name, do: [:membrane, :link, :new]
end
