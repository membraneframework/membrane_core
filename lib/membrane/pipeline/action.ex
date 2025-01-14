defmodule Membrane.Pipeline.Action do
  @moduledoc """
  This module contains type specifications of actions that can be returned
  from pipeline callbacks.

  Returning actions is a way of pipeline interaction with
  other components and parts of framework. Each action may be returned by any
  callback unless explicitly stated otherwise.
  """

  alias Membrane.{Child, ChildrenSpec, Pad}

  @typedoc """
  Action that manages the end of the component setup.

  By default, component setup ends with the end of `c:Membrane.Pipeline.handle_setup/2` callback.
  If `{:setup, :incomplete}` is returned there, setup lasts until `{:setup, :complete}`
  is returned from antoher callback.

  Untils the setup lasts, the component won't enter `:playing` playback.
  """
  @type setup :: {:setup, :incomplete | :complete}

  @typedoc """
  Action that sends a message to a child identified by name.
  """
  @type notify_child :: {:notify_child, {Child.name(), Membrane.ParentNotification.t()}}

  @typedoc """
  Action that instantiates children and links them according to `Membrane.ChildrenSpec`.

  Children's playback is changed to the current pipeline state.
  `c:Membrane.Pipeline.handle_spec_started/3` callback is executed once it happens.

  This is an example of a value that could be passed within `spec` action
  ```elixir
  child(:file_source, %My.File.Source{path: path})
  |> child(:demuxer, My.Demuxer)
  |> via_out(:video)
  |> child(:decoder, My.Decoder)
  |> child(:ai_filter, %My.AI.Filter{mode: :picasso_effect})
  |> child(:encoder, My.Encoder)
  |> via_in(:video)
  |> child(:webrtc_sink, My.WebRTC.Sink)
  ```
  along with it's visualisation

  ![](assets/images/spec_without_audio.svg)

  Returning another spec (on top of the previous one)
  ```elixir
  get_child(:demuxer)
  |> via_out(:audio)
  |> child(:scratch_remover, My.Scratch.Remover)
  |> via_in(:audio)
  |> get_child(:webrtc_sink)
  ```

  will result in having the following children's topology:

  ![](assets/images/spec_with_audio.svg)
  """
  @type spec :: {:spec, ChildrenSpec.t()}

  @typedoc """
  Action that stops, unlinks and removes specified child/children from the pipeline.

  A child name, list of children names, children group id or a list of children group ids can be specified
  as an argument.
  """
  @type remove_children ::
          {:remove_children, Child.name() | [Child.name()]}

  @typedoc """
  Action that removes link, which relates to specified child and pad.

  Removed link has to have dynamic pads on both ends.
  """
  @type remove_link :: {:remove_link, {Child.name(), Pad.ref()}}

  @typedoc """
  Starts a timer that will invoke `c:Membrane.Pipeline.handle_tick/3` callback
  every `interval` according to the given `clock`.

  The timer's `id` is passed to the `c:Membrane.Pipeline.handle_tick/3`
  callback and can be used for changing its interval via `t:timer_interval/0`
  or stopping it via `t:stop_timer/0`.

  If `interval` is set to `:no_interval`, the timer won't issue any ticks until
  the interval is set with `t:timer_interval/0` action.

  If no `clock` is passed, pipeline clock is chosen.

  Timers use `Process.send_after/3` under the hood.
  """
  @type start_timer ::
          {:start_timer,
           {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg() | :no_interval}
           | {timer_id :: any, interval :: Ratio.t() | Membrane.Time.non_neg() | :no_interval,
              clock :: Membrane.Clock.t()}}

  @typedoc """
  Changes interval of a timer started with `t:start_timer/0`.

  Permitted only from `c:Membrane.Pipeline.handle_tick/3`, unless the interval
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
  Action that replies to a `Membrane.Pipeline.call/3`. Can be returned only from the `c:Membrane.Pipeline.handle_call/3` callback, in
  which context the caller reference is available, under the `:from` key.
  """
  @type reply :: {:reply, message :: any}

  @typedoc """
  Action that replies to a `Membrane.Pipeline.call/3`. Useful when one does not want to reply in
  `c:Membrane.Pipeline.handle_call/3` callback. A caller reference is required to be passed, so one needs to save this
  reference from the `Membrane.Pipeline.CallbackContext.Call`, where it is available under the `:from` key.
  """
  @type reply_to :: {:reply_to, {GenServer.from(), message :: any}}

  @typedoc """
  Terminates the pipeline with given reason.

  Termination reason follows the OTP semantics:
  - Use `:normal` for graceful termination. If the pipeline has no children, it terminates
  immediately. Otherwise, it switches to the zombie mode, requests all the children to terminate,
  waits for them to terminate and then terminates itself. In the zombie mode, no pipeline callbacks
  are called and all messages and calls to the pipeline are ignored (apart from Membrane internal
  messages)
  - If the reason is other than `:normal`, the pipeline terminates immediately. The pipeline supervisor
  terminates all the children with the reason `:shutdown`
  - If the reason is neither `:normal`, `:shutdown` nor `{:shutdown, term}`, an error is logged
  """
  @type terminate :: {:terminate, reason :: :normal | :shutdown | {:shutdown, term} | term}

  @typedoc """
  Type describing the actions that can be returned from any pipeline callback.
  """
  @type common_actions ::
          setup
          | notify_child
          | spec
          | remove_children
          | remove_link
          | start_timer
          | timer_interval
          | stop_timer
          | reply_to
          | terminate

  @typedoc """
  Type describing the union of all actions that can be returned from pipeline callbacks.

  Returning actions is a way of pipeline interaction with its children and
  other parts of framework.
  """
  @type t :: reply | common_actions
end
