defmodule Membrane.Element.Action do
  @moduledoc """
  This module contains type specifications of actions that can be returned
  from element callbacks. Returning actions is a way of element interaction with
  other elements and parts of framework. Each action may be returned by any
  callback (despite `handle_init` and `handle_terminate`, as they do not return
  any actions) unless explicitly stated.
  """

  @typedoc """
  Causes sending a message to the pipeline.
  """
  @type message_t :: {:message, Message.t()}

  @typedoc """
  Causes sending an event through a pad (sink or source).

  Forbidden when playback state is stopped.
  """
  @type event_t :: {:event, {Pad.name_t(), Event.t()}}

  @typedoc """
  Allows to split callback execution into multiple applications of another callback
  (called from now sub-callback).

  Executions are synchronous in the element process, and each of them passes
  subsequent arguments from the args_list, along with the element state (passed
  as the last argument each time).

  Return value of each execution of sub-callback can be any valid return value
  of the original callback (this also means sub-callback can return any action
  valid for the original callback, unless expliciltly stated). Returned actions
  are executed immediately (their are NOT accumulated and executed after all
  sub-callback executions are finished).

  Useful when a long action is to be undertaken, and partial results need to
  be returned before entire process finishes (e.g. default implementation of
  `handle_process` uses split action to invoke `handle_process1` with each buffer)
  """
  @type split_t :: {:split, {callback_name :: atom, args_list :: [[any]]}}

  @typedoc """
  Causes sending caps through a pad (it must be source pad). Sended caps
  must fit constraints on the pad.

  Forbidden when playback state is stopped.
  """
  @type caps_t :: {:caps, {Pad.name_t(), Caps.t()}}

  @typedoc """
  Causes sending buffers through a pad (it must be source pad).

  Allowed only when playback state is playing.
  """
  @type buffer_t :: {:buffer, {Pad.name_t(), Buffer.t() | [Buffer.t()]}}

  @typedoc """
  Causes making a demand on a pad (it must be sink pad in pull mode). It does NOT
  cause _sending_ demand through the pad, but just _requesting_ some amount of data
  from `PullBuffer`, which _sends_ demands automatically when it runs out of data.
  Pad is guaranteed not to receive more data than demanded.

  Depending on element type and callback, it may contain different payloads or
  behave differently:

  In sinks:
  - Payload `{pad, size}` causes extending demand on given pad by given size.
  - Payload `{pad, {:set_to, size}}` earses current demand and sets it to given size.

  In filters:
  - Payload `{pad, size}` is only allowed from `handle_demand` callback. It overrides
  current demand.
  - Payload `{pad, {{:source, demanding_source_pad}, size}}` can be returned from
  any callback. `demanding_source_pad` is a pad which is to receive demanded
  buffers after they are processed.
  - Payload `{pad, {:self, size}}` makes demand act as if element was a sink,
  that is extends demand on a given pad. Buffers received as a result of the
  demand should be consumed by element itself or sent through a pad in `push` mode.

  Allowed only when playback state is playing.
  """
  @type demand_t ::
          {:demand, demand_common_payload_t | demand_filter_payload_t | demand_sink_payload_t}

  @type demand_filter_payload_t ::
          {Pad.name_t(), {:source, Pad.name_t()} | :self, size :: non_neg_integer}
  @type demand_sink_payload_t :: {Pad.name_t(), {:set_to, size :: non_neg_integer}}
  @type demand_common_payload_t :: Pad.name_t() | {Pad.name_t(), size :: non_neg_integer}

  @typedoc """
  Causes executing `handle_demand` callback with given pad (which must be a source
  pad in pull mode) if this demand is greater than 0.

  Useful when demand could not have been supplied when previous call to
  `handle_demand` happened, but some element-specific circumstances changed and
  it might be possible to supply it (at least partially).

  Allowed only when playback state is playing.
  """
  @type redemand_t :: {:redemand, Pad.name_t()}

  @typedoc """
  Causes sending buffers/caps/event to all source pads of element (or to sink
  pads when event occurs on the source pad). Used by default implementations
  of `handle_caps` and `handle_event` callbacks in filter.

  Allowed only in filters and from `handle_process`, `handle_caps` and `handle_event`
  callbacks, and when playback state is valid for buffer, caps or event action
  respectively.

  Keep in mind that `handle_process` can only forward buffers, `handle_caps` - caps
  and `handle_event` - events.
  """
  @type forward_t :: {:forward, Buffer.t() | [Buffer.t()] | Caps.t() | Event.t()}

  @typedoc """
  Causes suspending/resuming change of playback state.

  - `playback_change: :suspend` may be returned only from `handle_prepare`,
  `handle_play` and `handle_stop callbacks`, and defers playback state change
  until `playback_change: :resume` is returned.
  - `playback_change: :resume` may be returned from any callback, only when
  playback state change is suspended, and causes it to finish.

  There is no straight limit how long playback change can take, but keep in mind
  that it may affect application quality if not done quick enough.
  """
  @type playback_change_t :: {:playback_change, :suspend | :resume}

  @typedoc """
  Type that defines a single action that may be returned from element callbacks.
  Depending on element type, callback, current playback state and other
  circumstances there may be different actions available.
  """
  @type t ::
          event_t
          | message_t
          | split_t
          | caps_t
          | buffer_t
          | demand_t
          | redemand_t
          | forward_t
          | playback_change_t
end
