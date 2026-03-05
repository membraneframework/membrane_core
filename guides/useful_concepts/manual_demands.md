# Manual demands

Elements with `:manual` flow control pads have two responsibilities:

- **Output pads**: produce exactly the amount of data requested in the
  [`handle_demand/5`](`c:Membrane.Element.WithOutputPads.handle_demand/5`)
  callback.
- **Input pads**: explicitly request data using the
  [`:demand`](`t:Membrane.Element.Action.demand/0`) action — data only arrives
  after demand has been issued.

## Output pads and `handle_demand`

When downstream requests data, Membrane invokes `handle_demand/5` on the
element whose output pad is connected to that downstream. The callback receives
the pad name, the demanded amount, and the demand unit. The element is expected
to produce and send that amount of data.

The unit in which `demand_size` is expressed is resolved as follows:

1. If the **output pad** declares `demand_unit: :buffers | :bytes`, that unit
   is used.
2. Otherwise, if the linked **input pad** uses `:buffers` or `:bytes`, that
   unit is inherited.
3. Otherwise (e.g. the input pad uses a timestamp unit), the output pad
   inherits `:buffers`.

So the output pad can explicitly control the unit it receives demand in, but
timestamp units are not available on output pads.

### Producing buffers on demand

A source generating random data:

```elixir
defmodule MySource do
  use Membrane.Source

  def_output_pad :output,
    flow_control: :manual,
    accepted_format: _any

  @impl true
  def handle_demand(:output, demand_size, :buffers, _ctx, state) do
    buffers = Enum.map(1..demand_size, fn _ ->
      %Membrane.Buffer{payload: :crypto.strong_rand_bytes(256)}
    end)
    {[buffer: {:output, buffers}], state}
  end

  @impl true
  def handle_demand(:output, demand_size, :bytes, _ctx, state) do
    buffer = %Membrane.Buffer{payload: :crypto.strong_rand_bytes(demand_size)}
    {[buffer: {:output, buffer}], state}
  end
end
```

### Redemand

Sometimes producing all demanded buffers at once is not possible or not
desired — for example when the element generates one buffer at a time. In that
case, return the [`:redemand`](`t:Membrane.Element.Action.redemand/0`) action
alongside the buffer. Membrane will then invoke `handle_demand` again with the
demand reduced by the size of what was just sent.

```elixir
@impl true
def handle_demand(:output, _demand_size, :buffers, _ctx, state) do
  buffer = %Membrane.Buffer{payload: :crypto.strong_rand_bytes(256)}
  {[buffer: {:output, buffer}, redemand: :output], state}
end
```

Each invocation produces one buffer and returns `:redemand`. This repeats,
with demand shrinking by 1 on each call, until demand reaches 0 — at which
point `handle_demand` is not called again until new demand arrives from
downstream.

## Input pads and the demand action

To receive data on a `:manual` input pad, the element must issue a
[`:demand`](`t:Membrane.Element.Action.demand/0`) action. The demand unit
is declared in the input pad spec.

### `:buffers` and `:bytes`

#### Example: a sink demanding buffers

Below is a sink that every second demands 5 buffers and appends their payloads
to a file. This sink is contrived and exists only to demonstrate the demand
mechanism.

```elixir
defmodule MyDemoSink do
  use Membrane.Sink

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: _any

  @impl true
  def handle_playing(_ctx, state) do
    {[start_timer: {:demand_timer, Membrane.Time.seconds(1)},
      demand: {:input, 5}], state}
  end

  @impl true
  def handle_tick(:demand_timer, _ctx, state) do
    {[demand: {:input, 5}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    File.write!("output.bin", buffer.payload, [:append])
    {[], state}
  end
end
```

#### Example: demanding bytes

The same sink, but demanding 100 bytes at a time instead of 5 buffers:

```elixir
def_input_pad :input,
  flow_control: :manual,
  demand_unit: :bytes,
  accepted_format: _any

@impl true
def handle_tick(:demand_timer, _ctx, state) do
  {[demand: {:input, 100}], state}
end
```

When demanding in bytes, if a buffer boundary does not align with the requested
byte count, the buffer is split. Both fragments share the same metadata and
timestamps as the original buffer.

#### Declarative nature of demands

The `:demand` action **overwrites** the current demand — it does not add to it.
Issuing `demand: {:input, 5}` sets the demand to 5 regardless of how much
demand was already pending.

This matters when a new demand is issued before the previous one is fully
satisfied. For example, if you demand 5, receive 3 buffers, then demand 5
again:

| Event | Demand |
|-------|--------|
| `demand: {:input, 5}` | 5 |
| buffer received | 4 |
| buffer received | 3 |
| buffer received | 2 |
| `demand: {:input, 5}` | 5 ← overwrites 2 |
| buffer received | 4 |
| buffer received | 3 |
| buffer received | 2 |
| buffer received | 1 |
| buffer received | 0 |

Total received: **8**, not 10. The remaining 2 from the first demand were
discarded when the second `demand: {:input, 5}` was issued.

If you need to accumulate demand rather than overwrite it, use the function
form:

```elixir
{[demand: {:input, &(&1 + 5)}], state}
```

### Timestamp demand units

Timestamp demand units let an element request buffers by specifying a
**timestamp threshold** rather than a count or byte size. The element receives
all buffers up to and including the first one whose timestamp meets or exceeds
the demanded value.

Timestamp demand units are only applicable to **input pads**. Output pads do
not support them. If an input pad uses a timestamp demand unit and the linked
upstream element's output pad does not specify a `demand_unit`, that element
will receive `handle_demand/5` with demand expressed in `:buffers`.

#### Available variants

- `{:timestamp, :pts}` — demand is expressed in terms of each buffer's PTS.
- `{:timestamp, :dts}` — demand is expressed in terms of each buffer's DTS.
- `:timestamp` or `{:timestamp, :dts_or_pts}` — uses DTS if present on a
  buffer, falls back to PTS.

#### How timestamp demands work

The demand value is a `t:Membrane.Time.t/0` duration (in nanoseconds),
interpreted relative to an **offset** — the timestamp of the very first buffer
ever received on the pad. You never need to know the actual starting timestamp;
all demand values are expressed as durations from that origin.

When you issue `demand: {:input, t}`, Membrane delivers all buffered buffers
whose timestamp (minus the offset) is strictly less than `t`, plus the first
buffer whose timestamp (minus the offset) equals or exceeds `t`. This means
that **if you demand a value greater than the last received buffer's timestamp,
you are guaranteed to receive at least one new buffer**.

#### Incrementing demands

To receive a continuous stream in time-based chunks, always demand a value
larger than the timestamp of the last received buffer. Issuing a demand at or
below the last received timestamp will result in a warning and no buffers being
delivered.

#### Example: a sink consuming one second of data per second

```elixir
defmodule MyTimestampSink do
  use Membrane.Sink

  # For demonstration purposes only.

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: {:timestamp, :pts},
    accepted_format: _any

  @impl true
  def handle_playing(_ctx, state) do
    {[start_timer: {:demand_timer, Membrane.Time.seconds(1)},
      demand: {:input, Membrane.Time.seconds(1)}],
     %{state | next_demand: Membrane.Time.seconds(2)}}
  end

  @impl true
  def handle_tick(:demand_timer, _ctx, state) do
    {[demand: {:input, state.next_demand}],
     %{state | next_demand: state.next_demand + Membrane.Time.seconds(1)}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    File.write!("output.bin", buffer.payload, [:append])
    {[], state}
  end
end
```

Each timer tick advances the demanded threshold by one second: `1s`, `2s`,
`3s`, … All values are measured from the PTS of the very first buffer received
on `:input`, so each demand naturally covers the next one-second slice of the
stream.

> #### Buffers must carry timestamps {: .warning}
>
> Every buffer must have its relevant timestamp field (`:pts` or `:dts`) set to
> a non-`nil` value. Missing timestamps will cause incorrect behavior.

> #### Prefer DTS for encoded video {: .warning}
>
> PTS can be non-monotonic in streams with B-frames. Prefer
> `{:timestamp, :dts}` when DTS is available and monotonic, to avoid warnings.

## Filters: manual input and output

A filter with both a manual input and a manual output is the most common case
for manual flow control. The canonical pattern is:

- **`handle_demand`** — propagate the demand upstream by returning a `:demand`
  action on the input pad.
- **`handle_buffer`** — process the incoming buffer and forward it (possibly
  modified) downstream via a `:buffer` action.

```elixir
defmodule MyFilter do
  use Membrane.Filter

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: _any

  def_output_pad :output,
    flow_control: :manual,
    accepted_format: _any

  @impl true
  def handle_demand(:output, demand_size, :buffers, _ctx, state) do
    {[demand: {:input, demand_size}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    processed = %{buffer | payload: process(buffer.payload)}
    {[buffer: {:output, processed}], state}
  end

  defp process(payload), do: payload
end
```

> #### Do not use redemand in a filter's `handle_demand` {: .warning}
>
> Returning `:redemand` from `handle_demand` in a filter is illegal.
> `handle_demand` should propagate the demand to the input pad and return.
> Processing happens in `handle_buffer` when the data actually arrives.
