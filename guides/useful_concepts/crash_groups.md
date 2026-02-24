# Crash groups

Crash groups provide a mechanism to manage the lifecycle of elements within a pipeline when one of them fails. By grouping elements together, you can ensure that a crash in one part of the pipeline triggers a coordinated restart or termination of related elements, maintaining system consistency.

## Overview

In Membrane, elements and bins are Elixir processes. By default, if an element that is not inside a crash group crashes, it leads to the crash of the whole pipeline.

The most fundamental functionality of crash groups is to separate the crash of a specific element from the rest of the pipeline. Usually, if an element is likely to crash (e.g. it interacts with unstable external resources), it is placed in a crash group along with other elements whose functioning is inextricably connected to it. This prevents a localized failure from bringing down the entire system and allows for controlled recovery of specific logical units. By doing so, it also cleans up components that would have to be restarted or killed anyway.

## Defining Crash Groups

Crash groups are defined in the `spec` within your pipeline or bin. To create a crash group, you have to define a group name and set `crash_group_mode` to `:temporary`, like in the example below:

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

## Behavior

When an element belonging to a crash group crashes:
1. All other elements in the same crash group are terminated by the pipeline.
2. The pipeline's `handle_crash_group_down/3` callback is invoked.
3. You can decide whether to restart the group, ignore the failure, or handle this situation any other way.

## Flow of all callbacks reated to a crash within a crash group.

Let's assume, that in `:filter` spawned in `MyPipeline` raised with message `"internal error"`.

### Handling termination of the crash itiator

The first callback, that will be executed in `MyPipeline`, is

```elixir
@impl true
def handle_child_terminated(:filter, context, state) do
  # ...
end
```

`context` passed to this callback will contain few extra fileds:
  * `context.exit_reason` - in this case equals `{%RuntimeError{message: "internal error"}, _stacktrace}`. 
  * `context.group_name` - because `:filter` was spawned inside `:my_group` group, it equals `:my_group`. If a child is spawned beyond any crash group and is terminated gracefully, value of this field is `nil`.
  * `context.crash_initiator` - the same as child's reference, which is `:filter`.
  
`:filter` won't be present in `context.children`, so you could respawn it here, however it is suggested to do it in `handle_crash_group_down/3` later.

### Terminating other children within the crash group that explodes 

Because one of children from crash group `:my_group` ungracefully crashed, the rest of children from this group will be terminated as well. 

Therefore, Membrane will terminate `:source` and `:sink` in random order. After each termination, `MyPipeline` will execute 

```elixir
@impl true
def handle_child_terminated(child, context, state) do
  # ...
end
```

callback. Each time, `context` will contain following extra fields: 
  * `context.exit_reason` - equals `{:shutdown, :membrane_crash_group_kill}`.
  * `context.group_name` - equals `:my_group`.
  * `context.crash_initiator` - equals `:filter`.

Note, that `context.children` map always contains only children that are still alive. E.g. if `:source` is terminated first, `hanlde_child_terminated(:source, context, state)` will contain only `:sink` in `context.children` map and for `hanlde_child_terminated(:sink, context, state)` `context.children` will be empty.

Of course, `MyPipeline` could possibly spawn another children beyond `:source`, `:filter` and `:sink`, inside different crash groups or beyond any crash group. In such a case, `context.children` would contain all of them normally and these children wouldn't be interrupted by the crash of `:my_group` members. The main goal of crash groups is to limit the consequences of the child's crash only to children with the same crash group.

### Handling the crash group down

Then, when all members of a crash group are terminated, `MyPipeline` will execute 

```elixir 
@impl true
def handle_crash_group_down(:my_group, context, state) do
  # ...
end
```

`context` passed as a third argument to `handle_crash_group_down/3` callback contains 3 additional fields:
 - `context.crash_initiator` - name or reference of the child that crashed first and caused the crash group to explode. In this case, equals `:filter`
 - `context.crash_reason` - the reason with which `context.crash_initiator` crashed. In this case, equals `{%RuntimeError{message: "internal error"}, _stacktrace}`.
 - `context.members` - names/references of all children that were in the crash group. In this case, equals `[:source, :filter, :sink]`

When `handle_crash_group_down/3` is executed, you can be sure that all group members are already terminated. It is a suggested place, to e.g. respawn crash group. Doing so in `handle_child_terminated/3` might lead to some problems, because the order of group members termination might vary. Moreover, if pipeline or bin terminates its children gracefully, using `t:Membrane.Pipline.Action.remove_children()` action, `handle_child_terminated/3` callback will be also executed with `context.exit_reason` set to `normal`. 
