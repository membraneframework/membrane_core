# Crash Groups

Crash groups provide a mechanism to manage the lifecycle of children (elements or bins) within a pipeline when one of them fails. By grouping children together, you can ensure that a crash in one part of the pipeline triggers a coordinated restart or termination of related elements and bins, maintaining system consistency.

## Overview

In Membrane, elements and bins are Elixir processes. By default, if a child (element or bin) that is not inside a crash group crashes, it leads to the crash of the whole pipeline.

The fundamental purpose of crash groups is to isolate the crash of a specific child from the rest of the pipeline. If an child is likely to crash (e.g., it interacts with unstable external resources), it is usually assigned to a crash group containing all children inextricably linked to its operation. This prevents a localized failure from bringing down the entire system and allows for the controlled recovery of specific logical units. This approach also ensures that components generally needing a restart or termination are cleaned up correctly.

## Defining Crash Groups

Crash groups are defined in the `spec` within your pipeline or bin. They are built upon the concept of **Children Groups**, which allow aggregating spawned children into easily identifiable groups.

To create a crash group, you must assign children to a group using the `group` option and set the `crash_group_mode` to `:temporary`. This turns a regular group into a crash group, enabling the crash handling behavior.

```elixir
defmodule MyPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _opts) do
    spec = 
      child(:source, MySource)
      |> child(:filter, MyFilter)
      |> child(:sink, MySink)

    {[spec: {spec, group: :my_group, crash_group_mode: :temporary}], %{}}
  end
end
```

In the example above, `:source`, `:filter`, and `:sink` are all assigned to the same group `:my_group`. Because `crash_group_mode` is set to `:temporary`, this group functions as a crash group.

## Behaviour

When a child belonging to a crash group crashes:
1. All other children in the same crash group are terminated by the pipeline.
2. The pipeline's `c:Membrane.Pipeline.handle_crash_group_down/3` callback is invoked.
3. You can decide whether to restart the group, ignore the failure, or handle the situation in another way.

## Flow of callbacks triggered by a crash within a crash group

Let's assume a `:filter` element spawned in `MyPipeline` raises an error with the message `"internal error"`.

### Handling termination of the crash initiator

The first callback executed in `MyPipeline` will be:

```elixir
@impl true
def handle_child_terminated(:filter, context, state) do
  # ...
end
```

The `context` passed to this callback will contain a few extra fields:
  * `context.exit_reason` - in this case, it equals `{%RuntimeError{message: "internal error"}, _stacktrace}`. 
  * `context.group_name` - because `:filter` was spawned inside the `:my_group` group, this equals `:my_group`. If a child is spawned outside any crash group and terminates gracefully, the value of this field is `nil`.
  * `context.crash_initiator` - the same as the child's reference, which is `:filter`.
  
Since `:filter` is no longer present in `context.children`, you could potentially respawn it here. However, it is recommended to do so later in `c:Membrane.Pipeline.handle_crash_group_down/3`.

### Terminating other children within the failing crash group

Because one child from the crash group `:my_group` crashed ungracefully, the remaining children in that group will also be terminated. 

Therefore, Membrane will terminate `:source` and `:sink` (in random order). After each termination, `MyPipeline` will execute the following callback:

```elixir
@impl true
def handle_child_terminated(child, context, state) do
  # ...
end
```

Each time, the `context` will contain the following extra fields: 
  * `context.exit_reason` - equals `{:shutdown, :membrane_crash_group_kill}`.
  * `context.group_name` - equals `:my_group`.
  * `context.crash_initiator` - equals `:filter`.

Note that the `context.children` map always contains only the children that are still alive. For example, if `:source` is terminated first, `handle_child_terminated(:source, context, state)` will contain only `:sink` in the `context.children` map. Subsequently, for `handle_child_terminated(:sink, context, state)`, `context.children` will be empty.

`MyPipeline` could potentially spawn children other than  `:source`, `:filter`, and `:sink` - either in different crash groups or outside any crash group. In such cases, `context.children` would contain all of them normally, and these children would not be interrupted by the crash of `:my_group` members. The main goal of crash groups is to limit the consequences of a child's crash to only those children within the same group.

### Recovering from a crash group failure

Finally, when all members of the crash group are terminated, `MyPipeline` will execute:

```elixir 
@impl true
def handle_crash_group_down(:my_group, context, state) do
  # ...
end
```

The `context` passed as the third argument to the `handle_crash_group_down/3` callback contains three additional fields:
 - `context.crash_initiator` - the name or reference of the child that crashed first and caused the group to fail. In this case, it equals `:filter`.
 - `context.crash_reason` - the reason with which `context.crash_initiator` crashed. In this case, it equals `{%RuntimeError{message: "internal error"}, _stacktrace}`.
 - `context.members` - names/references of all children that were in the crash group. In this case, it equals `[:source, :filter, :sink]`.

When `handle_crash_group_down/3` is executed, you can be sure that all group members have already been terminated. This is the suggested place to recover from a group failer, e.g. by respawning all crash group members. Doing so in `handle_child_terminated/3` might lead to issues because the termination order of group members can vary. Moreover, if a pipeline or bin terminates its children gracefully (using the `t:Membrane.Pipeline.Action.remove_children()` action), the `c:Membrane.Pipeline.handle_child_terminated/3` callback will also be executed, but with `context.exit_reason` set to `normal`.


## Callback Contexts

For more information about callback contexts, refer to the documentation for `t:Membrane.Pipeline.CallbackContext.t()`, `t:Membrane.Bin.CallbackContext.t()`, and `t:Membrane.Element.CallbackContext.t()`.

## Bins

Although the example above demonstrates using crash groups within a `Membrane.Pipeline`, they function in the same way within a `Membrane.Bin`.