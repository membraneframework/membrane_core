defmodule Membrane.Bin.Action do
  @moduledoc """
  This module contains type specifications of actions that can be returned
  from bin callbacks.

  Returning actions is a way of bin interaction with
  other components and parts of framework. Each action may be returned by any
  callback unless explicitly stated otherwise.
  """

  alias Membrane.{Child, ChildrenSpec}

  @typedoc """
  Action that sends a message to a child identified by name.
  """
  @type notify_child_t ::
          {:notify_child, {Child.name_t(), Membrane.ParentNotification.t()}}

  @typedoc """
  Sends a message to the parent.
  """
  @type notify_parent_t :: {:notify_parent, Membrane.ChildNotification.t()}

  @typedoc """
  Action that instantiates children and links them according to `Membrane.ChildrenSpec`.

  Children's playback is changed to the current bin playback.
  `c:Membrane.Parent.handle_spec_started/3` callback is executed once the children are spawned.
  """
  @type spec_t :: {:spec, ChildrenSpec.t()}

  @typedoc """
  Action that stops, unlinks and removes specified child/children from the bin.
  """
  @type remove_child_t ::
          {:remove_child,
           Child.name_t()
           | [Child.name_t()]}

  @typedoc """
  Starts a timer that will invoke `c:Membrane.Bin.handle_tick/3` callback
  every `interval` according to the given `clock`.

  The timer's `id` is passed to the `c:Membrane.Bin.handle_tick/3`
  callback and can be used for changing its interval via `t:timer_interval_t/0`
  or stopping it via `t:stop_timer_t/0`.

  If `interval` is set to `:no_interval`, the timer won't issue any ticks until
  the interval is set with `t:timer_interval_t/0` action.

  If no `clock` is passed, parent clock is chosen.

  Timers use `Process.send_after/3` under the hood.
  """
  @type start_timer_t ::
          {:start_timer,
           {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg_t() | :no_interval}
           | {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg_t() | :no_interval,
              clock :: Membrane.Clock.t()}}

  @typedoc """
  Changes interval of a timer started with `t:start_timer_t/0`.

  Permitted only from `c:Membrane.Bin.handle_tick/3`, unless the interval
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
  Terminates bin with given reason.

  Termination reason follows the OTP semantics:
  - Use `:normal` for graceful termination. Allowed only when the parent already requested termination,
  i.e. after `c:Membrane.Bin.handle_terminate_request/2` is called. If the bin has no children, it
  terminates immediately. Otherwise, it switches to the zombie mode, requests all the children to terminate,
  waits for them to terminate and then terminates itself. In the zombie mode, no bin callbacks
  are called and all messages and calls to the bin are ignored (apart from Membrane internal
  messages)
  - If the reason is other than `:normal`, the bin terminates immediately. The bin supervisor
  terminates all the children with the reason `:shutdown`
  - If the reason is neither `:normal`, `:shutdown` nor `{:shutdown, term}`, an error is logged
  """
  @type terminate_t :: {:terminate, reason :: :normal | :shutdown | {:shutdown, term} | term}

  @typedoc """
  Type describing actions that can be returned from bin callbacks.

  Returning actions is a way of bin interaction with its children and
  other parts of framework.
  """
  @type t ::
          notify_child_t
          | notify_parent_t
          | spec_t
          | remove_child_t
          | start_timer_t
          | timer_interval_t
          | stop_timer_t
          | terminate_t
end
