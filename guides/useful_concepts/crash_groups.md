# Crash groups

Crash groups provide a mechanism to manage the lifecycle of elements within a pipeline when one of them fails. By grouping elements together, you can ensure that a crash in one part of the pipeline triggers a coordinated restart or termination of related elements, maintaining system consistency.

## Overview

In Membrane, elements and bins are Elixir processes. By default, if an element that is not inside a crash group crashes, it leads to the crash of the whole pipeline.

The most fundamental functionality of crash groups is to separate the crash of a specific element from the rest of the pipeline. Usually, if an element is likely to crash (e.g. it interacts with unstable external resources), it is placed in a crash group along with other elements whose functioning is inextricably connected to it. This prevents a localized failure from bringing down the entire system and allows for controlled recovery of specific logical units. By doing so, it also cleans up components that would have to be restarted or killed anyway.

## Defining Crash Groups

Crash groups are defined in the `spec` within your pipeline or bin. You assign a crash group ID to a set of children.

```elixir
defmodule MyPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _opts) do
    spec = 
      child(:source, MySource)
      |> child(:filter, MyFilter)
      |> child(:sink, MySink)

    {[spec: {spec, crash_group: :audio_processing}], %{}}
  end
end
```

In the case above, the crash group ID is `:audio_processing`.

## Behavior

When an element belonging to a crash group crashes:
1. All other elements in the same crash group are terminated by the pipeline.
2. The pipeline's `handle_crash_group_down/3` callback is invoked.
3. You can decide whether to restart the group, ignore the failure, or terminate the pipeline.

## Handling Failures

To react to a crash group failure, implement the `handle_crash_group_down/3` callback:

```elixir
@impl true
def handle_crash_group_down(crash_group_id, context, state) do
  # Logic to restart the group or handle the error
  {[], state}
end
```

`context` passed to `handle_crash_group_down/3` callback contiains 3 additional fields, that usually don't occur in contexts of other callbacks:
 - `context.crash_initiator` - name or reference of the child that crashed, what caused crash group to explode.
 - `context.crash_reason` - the reason with which `context.crash_initiator` crashed.
 - `context.members` - names/references of all children that were in the crash group.

Question marks:
  - is crash group initiator in context.members?
  - what is the order in of: 
    * `handle_crash_group_down`
    * `handle_child_terminated`
    * removing children from `context.children`, so that it becames possible to respawn new children with the same names?
  - what is the relation between `handle_child_pad_removed` and `handle_crash_group_down`?



## Use Cases
## tutaj poniej mamy AI BS, no chodzi o to ze jak mamy element co sie wydupca, to nie chcemy zeby wszystko poszlo w piach, wiec wrzucamy go (i byc moze cos co i tak bysmy chcieli razem z nim zrestartowac) do crash groupy

- **Atomic logical units:** When a group of elements (like an encoder and its associated parser) cannot function independently.
- **Resource Cleanup:** Ensuring that if a consumer crashes, the producer is also stopped to prevent buffered data from leaking memory.
- **Error Recovery:** Grouping elements that require a specific initialization sequence that must be repeated upon failure.

