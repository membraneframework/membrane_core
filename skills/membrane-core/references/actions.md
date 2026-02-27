# Membrane Framework — Actions Reference

Actions are returned from callbacks as `{[action_list], state}`.

---

## Data Actions (Elements Only)

```elixir
{:buffer, {pad_ref, %Membrane.Buffer{payload: binary, pts: pts, dts: dts, metadata: map}}}
# Send a buffer on an output pad

{:stream_format, {pad_ref, %SomeFormat{}}}
# Send stream format on an output pad — must be sent before the first buffer

{:event, {pad_ref, %SomeEvent{}}}
# Send an event on any pad — can go upstream or downstream

{:end_of_stream, pad_ref}
# Signal end of stream on an output pad
```

---

## Flow Control Actions

```elixir
# Manual input pads (flow_control: :manual) only:
{:demand, {pad_ref, size}}       # request `size` more units from upstream
{:redemand, pad_ref}             # re-evaluate demand on an output pad

# Auto input pads (flow_control: :auto) only:
{:pause_auto_demand, pad_ref}    # temporarily stop auto-pulling from upstream
{:resume_auto_demand, pad_ref}   # resume auto-pulling
```

---

## Topology Actions (Pipeline and Bin)

```elixir
{:spec, children_spec}                  # spawn and/or link children
{:remove_children, name_or_list}        # stop and remove children by name
{:remove_link, {child_name, pad_ref}}   # unlink a dynamic pad only
```

---

## Communication Actions

```elixir
{:notify_parent, any_term}   # send notification to parent (Bin and Elements only)
                              # received in parent's handle_child_notification/4
```

---

## Component Control Actions

```elixir
{:setup, :complete | :incomplete}
# :incomplete — signals setup isn't done yet, delays :playing for the whole spec group
# :complete   — signals setup is done (use after returning :incomplete earlier)

{:terminate, reason}   # stop this component with the given reason
```

---

## Timer Actions

```elixir
{:start_timer, {name, interval}}              # start a periodic timer → fires handle_tick/3
{:stop_timer, name}                           # stop a named timer
{:timer_interval, {name, new_interval}}       # change interval of a running timer
```

`interval` is a `Membrane.Time.t()` value (integer nanoseconds). Use helpers like `Membrane.Time.milliseconds(100)`.

---

## Buffer Struct Reference

```elixir
%Membrane.Buffer{
  payload: binary,               # actual media data
  pts: Membrane.Time.t() | nil,  # presentation timestamp (nanoseconds)
  dts: Membrane.Time.t() | nil,  # decode timestamp (nanoseconds)
  metadata: map | nil            # arbitrary extra info
}
```
