defmodule Membrane.Telemetry do
  @moduledoc """
  Defines basic telemetry event types used by Membrane's Core.

  Membrane uses [Telemetry Package](https://hex.pm/packages/telemetry) for instrumentation and does not store or save any measurements by itself.

  It is user's responsibility to use some sort of event handler and metric reporter
  that will be attached to `:telemetry` package to process generated measurements.

  ## Instrumentation
  The following telemetric events are published by Membrane's Core components:

    * `[:membrane, :element | :bin | :pipeline, callback, :start | :stop | :exception]` -
    where `callback` is any possible `handle_*` function defined for a component. Metadata
    passed to these events is `t:callback_span_metadata/0`.
      * `:start` - when the components begins callback's execution
      * `:stop` - when the components finishes callback's execution
      * `:exception` - when the component crashes during callback's execution

    * `[:membrane, :datapoint, datapoint_type]` -
    where datapoint_type is any of the available datapoint types (see below).
    Metadata passed to these events is `t:datapoint_metadata/0`.

  ## Enabling specific datapoints
  A lot of datapoints can happen hundreds times per second such as registering that a buffer has been sent/processed.

  This behaviour can come with a great performance penalties but may be helpful for certain discoveries. To avoid any runtime overhead
  when the reporting is not necessary all spans/datapoints are hidden behind a compile-time feature flags.
  To enable a particular measurement one must recompile membrane core with the following config put inside
  user's application `config.exs` file:

  ```
      config :membrane_core,
        telemetry_flags: [
          tracked_callbacks: [
            bin: [:handle_setup, ...] | :all,
            element: [:handle_init, ...] | :all,
            pipeline: [:handle_init, ...] | :all
          ],
        datapoints: [:buffer, ...] | :all
        ]
    ```

  Datapoint metrics are to be deprecated in the future (2.0) in favor of spans. They are still available for now.

  Available datapoints are:
  * `:link` - reports the number of links created in the pipeline
  * `:buffer` - number of buffers being sent from a particular element
  * `:queue_len` - number of messages in element's message queue during GenServer's `handle_info` invocation
  * `:stream_format` - indicates that given element has received new stream format, value always equals '1'
  * `:event` - indicates that given element has received a new event, value always equals '1'
  * `:store` - reports the current size of a input buffer when storing a new buffer
  * `:take` - reports the number of buffers taken from the input buffer
  """

  alias Membrane.{Bin, ComponentPath, Element, Pipeline}

  @typedoc """
  Atom representation of Membrane components subject to telemetry reports
  """
  @type component_type :: :element | :bin | :pipeline

  @type callback_context ::
          Element.CallbackContext.t() | Bin.CallbackContext.t() | Pipeline.CallbackContext.t()

  @typedoc """
  Metadata passed to telemetry events emitted on component's callbacks.

  Fields:
  * `callback` - name of the callback function
  * `callback_args` - arguments passed to the callback
  * `callback_context` - context of the callback consistent with Membrane.*.CallbackContext
  * `component_path` - path of the component in the pipeline consistent with t:ComponentPath.path/0
  * `component_type` - atom representation of the base component type
  * `monotonic_time` - monotonic time when the callback was executed in native time unit
  * `state_before_callback` - state of the component before the callback execution
  * `state_after_callback` - state of the component after the callback execution, it's `nil` on :start and :exception events
  """
  @type callback_span_metadata :: %{
          callback: atom(),
          callback_args: [any()],
          callback_context: callback_context(),
          component_path: ComponentPath.path(),
          component_type: component_type(),
          monotonic_time: integer(),
          state_before_callback: Element.state() | Bin.state() | Pipeline.state(),
          state_after_callback: Element.state() | Bin.state() | Pipeline.state() | nil
        }

  @typedoc """
  Types of telemetry datapoints reported by Membrane Core
  """
  @type datapoint_type :: :link | :buffer | :queue_len | :stream_format | :event | :store | :take

  @typedoc """
  Metadata included with each telemetry event
  """
  @type datapoint_metadata :: %{
          datapoint: datapoint_type(),
          component_path: ComponentPath.path(),
          component_type: component_type()
        }

  @typedoc """
  Value of the link datapoint
  * parent_component_path - process path of link's parent
  * from - from element name
  * to - to element name
  * pad_from - from's pad name
  * pad_to - to's pad name
  """
  @type link_datapoint_value :: %{
          parent_component_path: String.t(),
          from: String.t(),
          to: String.t(),
          pad_from: String.t(),
          pad_to: String.t()
        }
  @type buffer_datapoint_value :: integer()
  @type queue_len_datapoint_value :: integer()
  @type stream_format_datapoint_value :: %{format: map(), pad_ref: String.t()}
  @type incoming_event_datapoint_value :: String.t()
  @type store_datapoint_value :: %{value: integer(), log_tag: String.t()}

  @typedoc """
  Value of the specific event gathered
  """
  @type datapoint_value :: %{
          value:
            buffer_datapoint_value()
            | queue_len_datapoint_value()
            | stream_format_datapoint_value()
            | incoming_event_datapoint_value()
            | store_datapoint_value()
            | integer()
        }

  @doc """
  Returns if the event type is configured to be gathered by Membrane's Core telemetry
  """
  @spec datapoint_gathered?(any()) :: boolean()
  defdelegate datapoint_gathered?(type), to: Membrane.Core.Telemetry

  @doc """
  Lists all components and their callbacks tracked by Membrane's Core telemetry
  """
  @spec tracked_callbacks() :: [
          pipeline: [atom()],
          bin: [atom()],
          element: [atom()]
        ]
  defdelegate tracked_callbacks, to: Membrane.Core.Telemetry

  @doc """
  Lists all possible components and their callbacks that can be gathered when telemetry is enabled
  """
  @spec tracked_callbacks_available() :: [
          pipeline: [atom()],
          bin: [atom()],
          element: [atom()]
        ]
  defdelegate tracked_callbacks_available, to: Membrane.Core.Telemetry
end
