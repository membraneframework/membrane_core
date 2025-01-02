# Lifecycle of Membrane Components

The lifecycle of Membrane Components is closely related to the execution of Membrane callbacks within these components. While there are some differences among the lifecycles of Membrane Pipelines, Bins, and Elements, they share many similarities. Let's explore the component lifecycle and identify differences depending on the type of component being addressed.

## Initialization
The first callback executed in every Membrane Component is `handle_init/2`. This function is executed synchronously and blocks the parent component, except in the case of a Membrane Pipeline, as it does not have a parent. It is advisable to avoid heavy computations within this function. `handle_init/2` is ideally used for spawning children in a pipeline or bin through the `:spec` action.

## Setup
Following `handle_init/2` is `handle_setup/2`, which is executed asynchronously. This is an optimal time to set up resources or perform other intensive operations required for the element to function properly.

## Linking pads
For components with pads having `availability: :on_request`, the corresponding `handle_pad_added/3` callbacks are called between `handle_setup/2` and `handle_playing/2` if they are linked in the same spec where the component was spawned. Linking the pad in a different spec from the one spawning the element may lead to `handle_pad_added/3` being invoked after `handle_playing/2`.

## Playing
Once setup is completed, a component can enter the `:playing` state by invoking the `handle_playing/2` callback. Note that:
- Components spawned within the same `:spec` always enter the `:playing` state simultaneously. If the setup process for one component takes longer, the others will wait.
- Elements and Bins wait for their parent to enter the `playing` state before executing `handle_playing/2`.
- By default, after `handle_setup/2`, a component's setup is considered complete. This behavior can be modified by returning `setup: :incomplete` from `handle_setup/2`. The component must then mark its setup as completed by returning `setup: :complete` from another callback, like `handle_info/3`, to enter `:playing` playback.

## Processing the data (applies only to Elements)
After `handle_playing/2`, Elements are prepared to process data flowing through their pads.

### Events
Events are one type of item that can be sent via an Element's pads and are managed in `handle_event/4`. Events can travel both upstream and downstream relative to the pad’s direction.

### Stream Formats
The stream format, which defines the type of data carried by `Membrane.Buffer`s, must be declared before the first data buffer and is managed in `handle_stream_format/4`.

### Start of Stream
This callback (`handle_start_of_stream`) is activated just before processing the first `Membrane.Buffer` from a specific input pad.

### Buffers
The core of multimedia processing involves handling `Membrane.Buffer`s, which contain multimedia payload and may also include metadata or timestamps, all managed within the `handle_buffer/4` callback.

### Demands
If the Element has pads with `flow_control: :manual`, entering `:playing` playback allows it to send demand using `:demand` action or to receive it in `handle_demand/5` callback.

## After processing the data
When an element determines that it will no longer send buffers from a specific pad, it can return `:end_of_stream` action to that pad. The linked element receives this in `handle_end_of_stream/3`. The parent component (either a Bin or Pipeline) is notified via `handle_element_end_of_stream/4`.

## Terminating
Typically, the last callback executed within a Membrane Component is `handle_terminate_request`. By default, it returns a `terminate: :normal` action, concluding the component's lifespan with the reason `:normal`. This behavior can be modified by overriding the default implementation, but ensure to return a `terminate: reason` elsewhere to avoid termination issues in your Pipeline.

## Callbacks not strictly related to the lifecycle
Some callbacks are not confined to specific stages of the Membrane Component lifecycle.

### Handling parent or child notification
`handle_parent_notification/3` and `handle_child_notification/4` can occur at any point during the component's lifecycle and are tasked with managing notifications from a parent or child component, respectively.

### Handling messages from non-Membrane Erlang Processes
The `handle_info/3` callback is present in all Membrane Components and `handle_call/3` in Membrane Pipelines. These can be triggered at any time while the component is alive, functioning similarly to their substituted in `GenServer`.