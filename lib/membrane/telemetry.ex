defmodule Membrane.Telemetry do
  @moduledoc """
  Defines basic telemetry event types used by Membrane's Core.

  Membrane uses [Telemetry Package](https://hex.pm/packages/telemetry) for instrumentation and does not store or save any measurements by itself.

  It is user's responsibility to use some sort of event handler and metric reporter
  that will be attached to `:telemetry` package to process generated measurements.

  ## Instrumentation
  The following events are published by Membrane's Core with following measurement types and metadata:

    * `[:membrane, :element | :bin | :pipeline, handler, :start | :stop | :exception]` -
    where handler is any possible handle_* function defined for a component.
      * `:start` - when the handler begins execution
      * `:stop` - when the handler finishes execution
      * `:exception` - when the component's handler crashes during execution

    * `[:membrane, :event, event_type]` -
    where event_type is any of the available event types (see below)

  ## Enabling specific events
  A lot of events can happen hundreds times per second such as registering that a buffer has been sent/processed.

  This behaviour can come with a great performance penalties but may be helpful for certain discoveries. To avoid any runtime overhead
  when the reporting is not necessary all events/events are hidden behind a compile-time feature flags.
  To enable a particular measurement one must recompile membrane core with the following config put inside
  user's application `config.exs` file:

  ```
      config :membrane_core,
        telemetry_flags: [
          tracked_callbacks: [
            [:handle_setup, ...] | :all
          ]
        events: [:buffer, ...] | :all
        ]
    ```

  Available events are:
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
  Metadata included with each telemetry component's handler profiled
  * callback - name of the callback function
  * callback_args - arguments passed to the callback
  * callback_context - context of the callback consistent with Membrane.*.CallbackContext
  * component_path - path of the component in the pipeline consistent with t:ComponentPath.path/0
  * component_type - atom representation of the base component type
  * internal_state_before - state of the component before the callback execution
  * internal_state_after - state of the component after the callback execution, it's `nil` on :start and :exception events
  """
  @type callback_event_metadata :: %{
          callback: atom(),
          callback_args: [any()],
          callback_context: callback_context(),
          component_path: ComponentPath.path(),
          component_type: component_type(),
          internal_state_before: Element.state() | Bin.state() | Pipeline.state(),
          internal_state_after: Element.state() | Bin.state() | Pipeline.state() | nil
        }

  @typedoc """
  Types of telemetry events reported by Membrane Core
  """
  @type event_type :: :link | :buffer | :queue_len | :stream_format | :event | :store | :take

  @typedoc """
  Metadata included with each telemetry event
  """
  @type event_metadata :: %{
          event: event_type(),
          component_path: ComponentPath.path(),
          component_type: component_type()
        }

  @typedoc """
  Value of the link event
  * parent_component_path - process path of link's parent
  * from - from element name
  * to - to element name
  * pad_from - from's pad name
  * pad_to - to's pad name
  """
  @type link_event_value :: %{
          parent_component_path: String.t(),
          from: String.t(),
          to: String.t(),
          pad_from: String.t(),
          pad_to: String.t()
        }
  @type buffer_event_value :: integer()
  @type queue_len_event_value :: integer()
  @type stream_format_event_value :: %{format: map(), pad_ref: String.t()}
  @type incoming_event_value :: String.t()
  @type store_event_value :: %{value: integer(), log_tag: String.t()}

  @typedoc """
  Value of the specific event gathered
  """
  @type event_value :: %{
          value:
            buffer_event_value()
            | queue_len_event_value()
            | stream_format_event_value()
            | incoming_event_value()
            | store_event_value()
            | integer()
        }

  @doc """
  Returns if the event type is configured to be gathered by Membrane's Core telemetry
  """
  @spec event_gathered?(any()) :: boolean()
  defdelegate event_gathered?(event_type), to: Membrane.Core.Telemetry

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
