defmodule Membrane.Element.Action do
  @moduledoc """
  This module contains type specifications of actions that can be returned
  from element callbacks.

  Returning actions is a way of element interaction with
  other elements and parts of framework. Each action may be returned by any
  callback unless explicitly stated otherwise.
  """

  alias Membrane.{Buffer, ChildNotification, Clock, Event, Pad, StreamFormat}

  @typedoc """
  Sends a message to the parent.
  """
  @type notify_parent_t :: {:notify_parent, ChildNotification.t()}

  @typedoc """
  Sends an event through a pad (input or output).

  Allowed only when playback is `playing`.
  """
  @type event_t :: {:event, {Pad.ref_t(), Event.t()}}

  @typedoc """
  Allows to split callback execution into multiple applications of another callback
  (called from now sub-callback).

  Executions are synchronous in the element process, and each of them passes
  subsequent arguments from the args_list, along with the element state (passed
  as the last argument each time).

  Return value of each execution of sub-callback can be any valid return value
  of the original callback (this also means sub-callback can return any action
  valid for the original callback, unless explicitly stated). Returned actions
  are executed immediately (they are NOT accumulated and executed after all
  sub-callback executions are finished).

  Useful when a long action is to be undertaken, and partial results need to
  be returned before entire process finishes (e.g. default implementation of
  `c:Membrane.Filter.handle_process_list/4` uses split action to invoke
  `c:Membrane.Filter.handle_process/4` with each buffer)
  """
  @type split_t :: {:split, {callback_name :: atom, args_list :: [[any]]}}

  @typedoc """
  Sends stream format through a pad.

  The pad must have output direction. Sent stream format must fit constraints on the pad.

  Allowed only when playback is `playing`.
  """
  @type stream_format_t :: {:stream_format, {Pad.ref_t(), StreamFormat.t()}}

  @typedoc """
  Sends buffers through a pad.

  The pad must have output direction.

  Allowed only when playback is playing.
  """
  @type buffer_t :: {:buffer, {Pad.ref_t(), Buffer.t() | [Buffer.t()]}}

  @typedoc """
  Makes a demand on a pad.

  The pad must have input direction and work in pull mode. This action does NOT
  entail _sending_ demand through the pad, but just _requesting_ some amount
  of data from pad's internal queue, which _sends_ demands automatically when it
  runs out of data.
  If there is any data available at the pad, the data is passed to
  `c:Membrane.Filter.handle_process_list/4`, `c:Membrane.Endpoint.handle_write_list/4`
  or `c:Membrane.Sink.handle_write_list/4` callback. Invoked callback is
  guaranteed not to receive more data than demanded.

  Demand size can be either a non-negative integer, that overrides existing demand,
  or a function that is passed current demand, and is to return the new demand.

  Allowed only when playback is playing.
  """
  @type demand_t :: {:demand, {Pad.ref_t(), demand_size_t}}
  @type demand_size_t :: pos_integer | (pos_integer() -> non_neg_integer())

  @typedoc """
  Executes `c:Membrane.Element.WithOutputPads.handle_demand/5` callback
  for the given pad if its demand is greater than 0.

  The pad must have output direction and work in pull mode.

  ## Redemand in Sources and Endpoints

  In case of Sources and Endpoints, `:redemand` is just a helper that simplifies element's code.
  The element doesn't need to generate the whole demand synchronously at `handle_demand`
  or store current demand size in its state, but it can just generate one buffer
  and return `:redemand` action.
  If there is still one or more buffers to produce, returning `:redemand` triggers
  the next invocation of `handle_demand`. In such case, the element is to produce
  next buffer and call `:redemand` again.
  If there are no more buffers demanded, `handle_demand` is not invoked and
  the loop ends.
  One more advantage of the approach with `:redemand` action is that produced buffers
  are sent one after another in separate messages and this can possibly improve
  the latency.

  ## Redemand in Filters

  Redemand in Filters is useful in a situation where not the entire demand of
  output pad has been satisfied and there is a need to send a demand for additional
  buffers through the input pad.
  A typical example of this situation is a parser that has not demanded enough
  bytes to parse the whole frame.

  ## Usage limitations
  Allowed only when playback is playing.
  """
  @type redemand_t :: {:redemand, Pad.ref_t()}

  @typedoc """
  Sends buffers/stream format/event to all output pads of element (or to input pads when
  event occurs on the output pad).

  Used by default implementations of
  `c:Membrane.Element.WithInputPads.handle_stream_format/4` and
  `c:Membrane.Element.Base.handle_event/4` callbacks in filter.

  Allowed only when _all_ below conditions are met:
  - element is filter,
  - callback is `c:Membrane.Filter.handle_process_list/4`,
  `c:Membrane.Element.WithInputPads.handle_stream_format/4`
  or `c:Membrane.Element.Base.handle_event/4`,
  - playback is `playing`

  Keep in mind that `c:Membrane.Filter.handle_process_list/4` can only
  forward buffers, `c:Membrane.Element.WithInputPads.handle_stream_format/4` - stream formats
  and `c:Membrane.Element.Base.handle_event/4` - events.
  """
  @type forward_t ::
          {:forward, Buffer.t() | [Buffer.t()] | StreamFormat.t() | Event.t() | :end_of_stream}

  @typedoc """
  Starts a timer that will invoke `c:Membrane.Element.Base.handle_tick/3` callback
  every `interval` according to the given `clock`.

  The timer's `id` is passed to the `c:Membrane.Element.Base.handle_tick/3`
  callback and can be used for changing its interval via `t:timer_interval_t/0`
  or stopping it via `t:stop_timer_t/0`.

  If `interval` is set to `:no_interval`, the timer won't issue any ticks until
  the interval is set with `t:timer_interval_t/0` action.

  If no `clock` is passed, parent's clock is chosen.

  Timers use `Process.send_after/3` under the hood.
  """
  @type start_timer_t ::
          {:start_timer,
           {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg_t() | :no_interval}
           | {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg_t() | :no_interval,
              clock :: Clock.t()}}

  @typedoc """
  Changes interval of a timer started with `t:start_timer_t/0`.

  Permitted only from `c:Membrane.Element.Base.handle_tick/3`, unless the interval
  was previously set to `:no_interval`.

  If the `interval` is `:no_interval`, the timer won't issue any ticks until
  another `t:timer_interval_t/0` action. Otherwise, the timer will issue ticks every
  new `interval`. The next tick after interval change is scheduled at
  `new_interval + previous_time`, where previous_time is the time of the latest
  tick or the time of returning `t:start_timer_t/0` action if no tick has been
  sent yet. Note that if `current_time - previous_time > new_interval`, a burst
  of `div(current_time - previous_time, new_interval)` ticks is issued immediately.
  """
  @type timer_interval_t ::
          {:timer_interval,
           {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg_t() | :no_interval}}

  @typedoc """
  Stops a timer started with `t:start_timer_t/0` action.

  This action is atomic: stopping timer guarantees that no ticks will arrive from it.
  """
  @type stop_timer_t :: {:stop_timer, timer_id :: any}

  @typedoc """
  This action sets the latency for the element.

  This action is not premitted in callback `c:Membrane.Element.Base.handle_init/2`.
  """
  @type latency_t :: {:latency, latency :: Membrane.Time.non_neg_t()}

  @typedoc """
  Marks that processing via a pad (output) has been finished and the pad instance
  won't be used anymore.

  Triggers `end_of_stream/3` callback at the receiver element.
  Allowed only when playback is in playing state.
  """
  @type end_of_stream_t :: {:end_of_stream, Pad.ref_t()}

  @typedoc """
  Terminates element with given reason.

  Termination reason follows the OTP semantics:
  - Use `:normal` for graceful termination. Allowed only when the parent already requested termination,
    i.e. after `c:Membrane.Element.Base.handle_terminate_request/2` is called
  - If reason is neither `:normal`, `:shutdown` nor `{:shutdown, term}`, an error is logged
  """
  @type terminate_t :: {:terminate, reason :: :normal | :shutdown | {:shutdown, term} | term}

  @typedoc """
  Type that defines a single action that may be returned from element callbacks.

  Depending on element type, callback, current playback and other
  circumstances there may be different actions available.
  """
  @type t ::
          event_t
          | notify_parent_t
          | split_t
          | stream_format_t
          | buffer_t
          | demand_t
          | redemand_t
          | forward_t
          | start_timer_t
          | stop_timer_t
          | latency_t
          | end_of_stream_t
          | terminate_t
end
