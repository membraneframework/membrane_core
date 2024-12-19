# Timer usage examples
Exampls below illustrate how to use `:start_timer`, `:timer_interval` and `:stop_timer` actions on the example of `Membrane.Source`, but the API looks the same for all kinds of the Membrane Components

### Emit empty buffer every 100 milliseconds
```elixir
defmodule MySource do
  use Membrane.Source

  def_output_pad :output, accepted_format: SomeFormat

  @impl true
  def handle_init(_ctx, _opts), do: {[], %{}}

  @impl true
  def handle_playing(_ctx, state) do
    interval_in_millis = 100
    interval = Membrane.Time.milliseconds(interval_in_millis)

    actions = [
      stream_format: %SomeFormat{},
      start_timer: {:some_timer, interval}
    ]

    {actions, state}
  end

  @impl true
  def handle_tick(:some_timer, _ctx, state) do
    buffer = %Membrane.Buffer{payload: ""}
    actions = [buffer: {:output, buffer}]
    {actions, state}
  end
end
```

### Emit empty buffer every 100 millisecond if parent hasn't stopped you
The source below accepts following notifications from the parent: 
 - `:pause` - after receiving it the source will pause sending buffers. The paused soure can be resumed again.
 - `:resume` - resumes sending buffers from the paused source.
 - `:stop` - the stopped source won't send any buffer again.

```elixir
defmodule MyComplexSource
  use Membrane.Source

  def_output_pad :output, accepted_format: SomeFormat

  @one_hundred_millis = Membrane.Time.milliseconds(100)

  @impl true
  def handle_init(_ctx, _opts), do: {[], %{status: nil}}

  @impl true 
  def handle_playing(_ctx, state) do
    interval_in_millis = 100
    interval = Membrane.Time.milliseconds(interval_in_millis)

    actions = [
      stream_format: %SomeFormat{},
      start_timer: {:some_timer, interval}
    ]

    {actions, %{state | status: :resumed}}
  end

  @impl true
  def handle_parent_notification(notification, ctx, _state) when ctx.playback == :stopped do
    raise "Cannot handle parent notification: #{inspect(notification)} before handle_palaying"
  end

  @impl true
  def handle_parent_notification(notification, _ctx, state) when notification in [:pause, :resume, :stop] do
    case notification do
      :pause when state.status == :resumed -> 
        {[], %{state | status: :pause_on_next_handle_tick}}

      :resume when state.status == :paused -> 
        actions = [timer_interval: {:some_timer, @one_hundred_millis}]
        {actions, %{state | status: :resumed}}

      :resume when state.status == :pause_on_next_handle_tick -> 
        {[], %{state | status: :resumed}}

      :stop -> 
        {[stop_timer: :some_timer], %{state | status: :stopped}}
    end
  end

  @impl true
  def handle_tick(:some_timer, _ctx, state) do
    case state.status do
      :resumed -> 
        buffer = %Membrane.Buffer{payload: ""}
        {[buffer: {:output, buffer}], state}

      :pause_on_next_handle_tick -> 
        actions = [timer_interval: :no_interval]
        {actions, %{state | status: :paused}}
    end
  end
end
```
