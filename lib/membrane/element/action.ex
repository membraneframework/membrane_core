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
  Action that manages the end of the component setup.

  By default, component setup ends with the end of `c:Membrane.Element.Base.handle_setup/2` callback.
  If `{:setup, :incomplete}` is returned there, setup lasts until `{:setup, :complete}`
  is returned from antoher callback.

  Untils the setup lasts, the component won't enter `:playing` playback.
  """
  @type setup :: {:setup, :incomplete | :complete}

  @typedoc """
  Sends a message to the parent.
  """
  @type notify_parent :: {:notify_parent, ChildNotification.t()}

  @typedoc """
  Sends an event through a pad (input or output).

  Allowed only when playback is `playing`.
  """
  @type event :: {:event, {Pad.ref(), Event.t()}}

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
  be returned before entire process finishes.
  """
  @type split :: {:split, {callback_name :: atom, args_list :: [[any]]}}

  @typedoc """
  Sends stream format through a pad.

  The pad must have output direction. Sent stream format must fit constraints on the pad.

  Allowed only when playback is `playing`.
  """
  @type stream_format :: {:stream_format, {Pad.ref(), StreamFormat.t()}}

  @typedoc """
  Sends buffers through a pad.

  The pad must have output direction.

  Allowed only when playback is playing.
  """
  @type buffer :: {:buffer, {Pad.ref(), Buffer.t() | [Buffer.t()]}}

  @typedoc """
  Makes a demand on a pad.

  The pad must have input direction and work in `:manual` flow control mode. This action does NOT
  entail _sending_ demand through the pad, but just _requesting_ some amount
  of data from pad's internal queue, which _sends_ demands automatically when it
  runs out of data.
  If there is any data available at the pad, the data is passed to
  `c:Membrane.WithInputPads.handle_buffer/4` callback. Invoked callback is
  guaranteed not to receive more data than demanded.

  Demand size can be either a non-negative integer, that overrides existing demand,
  or a function that is passed current demand, and is to return the new demand.

  Allowed only when playback is playing.
  """
  @type demand :: {:demand, {Pad.ref(), demand_size}}
  @type demand_size :: pos_integer | (pos_integer() -> non_neg_integer())

  @typedoc """
  Pauses auto-demanding on the specific pad.

  The pad must have input direction and work in `:auto` flow control mode.

  This action does not guarantee that no more buffers will arrive on the specific pad,
  but ensures, that demand on this pad will not increase until returning
  `#{inspect(__MODULE__)}.resume_auto_demand()` action. Number of buffers, that will
  arrive on the pad, depends on the behaviour of the elements earlier in the pipeline.

  When auto-demanding is already paused, this action has no effect.
  """
  @type pause_auto_demand :: {:pause_auto_demand, Pad.ref() | [Pad.ref()]}

  @typedoc """
  Resumes auto-demanding on the specific pad.

  The pad must have input direction and work in `:auto` flow control mode.

  This action reverts the effects of `#{inspect(__MODULE__)}.pause_auto_demand()` action.

  When auto demanding is not paused, this action has no effect.
  """
  @type resume_auto_demand :: {:resume_auto_demand, Pad.ref() | [Pad.ref()]}

  @typedoc """
  Executes `c:Membrane.Element.WithOutputPads.handle_demand/5` callback
  for the given pad (or pads), that have demand greater than 0.

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
  @type redemand :: {:redemand, Pad.ref() | [Pad.ref()]}

  @typedoc """
  Sends buffers/stream format/event/end of stream to all output pads of element (or to input
  pads when event occurs on the output pad).

  Used by default implementations of
  `c:Membrane.Element.WithInputPads.handle_stream_format/4`,
  `c:Membrane.Element.Base.handle_event/4` and
  `c:Membrane.Element.WithInputPads.handle_end_of_stream/3` callbacks in filter.

  Allowed only when _all_ below conditions are met:
  - element is filter,
  - callback is `c:Membrane.Element.WithInputPads.handle_buffer/4`,
  `c:Membrane.Element.WithInputPads.handle_stream_format/4`,
  `c:Membrane.Element.Base.handle_event/4` or `c:Membrane.Element.WithInputPads.handle_end_of_stream/3`
  - playback is `playing`

  Keep in mind that `c:Membrane.WithInputPads.handle_buffer/4` can only
  forward buffers, `c:Membrane.Element.WithInputPads.handle_stream_format/4` - stream formats.
  `c:Membrane.Element.Base.handle_event/4` - events and
  `c:Membrane.Element.WithInputPads.handle_end_of_stream/3` - ends of streams.
  """
  @type forward ::
          {:forward, Buffer.t() | [Buffer.t()] | StreamFormat.t() | Event.t() | :end_of_stream}

  @typedoc """
  Starts a timer that will invoke `c:Membrane.Element.Base.handle_tick/3` callback
  every `interval` according to the given `clock`.

  The timer's `id` is passed to the `c:Membrane.Element.Base.handle_tick/3`
  callback and can be used for changing its interval via `t:timer_interval/0`
  or stopping it via `t:stop_timer/0`.

  If `interval` is set to `:no_interval`, the timer won't issue any ticks until
  the interval is set with `t:timer_interval/0` action.

  If no `clock` is passed, parent's clock is chosen.

  Timers use `Process.send_after/3` under the hood.
  """
  @type start_timer ::
          {:start_timer,
           {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg() | :no_interval}
           | {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg() | :no_interval,
              clock :: Clock.t()}}

  @typedoc """
  Changes interval of a timer started with `t:start_timer/0`.

  Permitted only from `c:Membrane.Element.Base.handle_tick/3`, unless the interval
  was previously set to `:no_interval`.

  If the `interval` is `:no_interval`, the timer won't issue any ticks until
  another `t:timer_interval/0` action. Otherwise, the timer will issue ticks every
  new `interval`. The next tick after interval change is scheduled at
  `new_interval + previous_time`, where previous_time is the time of the latest
  tick or the time of returning `t:start_timer/0` action if no tick has been
  sent yet. Note that if `current_time - previous_time > new_interval`, a burst
  of `div(current_time - previous_time, new_interval)` ticks is issued immediately.
  """
  @type timer_interval ::
          {:timer_interval,
           {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg() | :no_interval}}

  @typedoc """
  Stops a timer started with `t:start_timer/0` action.

  This action is atomic: stopping timer guarantees that no ticks will arrive from it.
  """
  @type stop_timer :: {:stop_timer, timer_id :: any}

  @typedoc """
  This action sets the latency for the element.

  This action is permitted only in callback `c:Membrane.Element.Base.handle_init/2`.
  """
  @type latency :: {:latency, latency :: Membrane.Time.non_neg()}

  @typedoc """
  Marks that processing via a pad (output) has been finished and the pad instance
  won't be used anymore.

  Triggers `end_of_stream/3` callback at the receiver element.
  Allowed only when playback is in playing state.
  """
  @type end_of_stream :: {:end_of_stream, Pad.ref()}

  @typedoc """
  Terminates element with given reason.

  Termination reason follows the OTP semantics:
  - Use `:normal` for graceful termination. Allowed only when the parent already requested termination,
    i.e. after `c:Membrane.Element.Base.handle_terminate_request/2` is called
  - If reason is neither `:normal`, `:shutdown` nor `{:shutdown, term}`, an error is logged
  """
  @type terminate :: {:terminate, reason :: :normal | :shutdown | {:shutdown, term} | term}

  @typedoc """
  Type that defines a single action that may be returned from element callbacks.

  Depending on element type, callback, current playback and other
  circumstances there may be different actions available.
  """
  @type t ::
          setup
          | event
          | notify_parent
          | split
          | stream_format
          | buffer
          | demand
          | redemand
          | pause_auto_demand
          | resume_auto_demand
          | forward
          | start_timer
          | timer_interval
          | stop_timer
          | latency
          | end_of_stream
          | terminate
end
