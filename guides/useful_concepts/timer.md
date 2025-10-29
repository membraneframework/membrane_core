# Timer usage examples
Examples below illustrate how to use `:start_timer`, `:timer_interval` and `:stop_timer` actions on the example of `Membrane.Source`, but the API looks the same for all kinds of the Membrane Components

### Simple example
The example below emits an empty buffer every 100 milliseconds.

```elixir
defmodule MySource do
  use Membrane.Source

  def_output_pad :output, accepted_format: SomeFormat

  @impl true
  def handle_init(_ctx, _opts), do: {[], %{}}

  @impl true
  def handle_playing(_ctx, state) do
    # let's start a timer named :my_timer that will tick every 100 milliseconds ...

    start_timer_action = [
      start_timer: {:my_timer, Membrane.Time.milliseconds(100)}
    ]
    
    # ... and send a stream format
    actions = start_timer_action ++ [stream_format: {:output, %SomeFormat{}}]
    {actions, state}
  end

  # this callback is executed every 100 milliseconds
  @impl true
  def handle_tick(:my_timer, ctx, state) do
    actions = [buffer: {:output, %Membrane.Buffer{payload: ""}}]
    {actions, state}
  end
end
```

### Advanced example
The example below emits an empty buffer every 100 milliseconds if it hasn't been stopped or paused by the parent.

The source accepts the following notifications from the parent: 
 - `:pause` - after receiving it the source will pause sending buffers. The paused source can be resumed again.
 - `:resume` - resumes sending buffers from the paused source.
 - `:stop` - the stopped source won't send any buffer again.

```elixir
defmodule MyComplexSource
  use Membrane.Source

  def_output_pad :output, accepted_format: SomeFormat

  @impl true
  def handle_init(_ctx, _opts) do 
    # after starting a timer, the status will always be either :resumed, :paused 
    # or :pause_on_next_handle_tick
    {[], %{status: nil}}
  end

  @impl true 
  def handle_playing(_ctx, state) do
    # let's start a timer named :my_timer ...
    start_timer_action = [
      start_timer: {:my_timer, Membrane.Time.milliseconds(100)}
    ]
    
    # ... and send a stream format
    actions = start_timer_action ++ [stream_format: {:output, %SomeFormat{}}]
    {actions, %{state | status: :resumed}}
  end

  @impl true
  def handle_parent_notification(notification, _ctx, state) when notification in [:pause, :resume, :stop] do
    case notification do
      :pause when state.status == :resumed -> 
        # let's postpone pausing :my_timer to the upcoming handle_tick
        {[], %{state | status: :pause_on_next_handle_tick}}

      :resume when state.status == :paused -> 
        # resume :my_timer by returning :timer_interval action
        actions = [timer_interval: {:my_timer, Membrane.Time.milliseconds(100)}]
        {actions, %{state | status: :resumed}}

      :resume when state.status == :pause_on_next_handle_tick -> 
        # case when we receive :pause and :resume notifications without a tick 
        # between them
        {[], %{state | status: :resumed}}

      :stop -> 
        # stop :my_timer using :stop_timer action
        {[stop_timer: :my_timer], %{state | status: :stopped}}
    end
  end

  @impl true
  def handle_tick(:my_timer, _ctx, state) do
    case state.status do
      :resumed -> 
        buffer = %Membrane.Buffer{payload: ""}
        {[buffer: {:output, buffer}], state}

      :pause_on_next_handle_tick -> 
        # pause :my_timer using :timer_interval action with interval set to :no_interval
        actions = [timer_interval: {:my_timer, :no_interval}]
        {actions, %{state | status: :paused}}
    end
  end
end
```
