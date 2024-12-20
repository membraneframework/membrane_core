# Lifecycle of Membrane Components

Lifecycle of Membrane Components is strictly related to execution of Membrane callbacks withing these Components.
Although there are some differences between lifecycles of Membrane Pipelines, Bins and Elements, they are very similar to each other.
So let's take a look at what the component lifecycle looks like and what are the differences depending on the type of the Component we are dealing with.

## Initialization
The first callback, that is executed in every Membrane Component, is handle_init/2.
handle_init is always executed synchronously and blocks the parent component (the exception is Membrane Pipeline, that never has a parent component), so it's good to avoid heavy computations within it.
`handle_init` is a good place to spawn pipeline's or bin's children in the `:spec` action.

## Setup
The next callback after handle_init is `handle_setup`, that is executed asynchronusly and it is a good place to e.g. setup some resources or execute other heavy operations, that are necessary 
for the element to play.

## Linking the pads 
If the Component had some pads with `availability: :on_request` linked in the same `spec`, where it was spawned, the appropriate `handle_pad_added` callbacks will be invoked between `handle_setup` and `handle_playing`.
Linking the pad with `availability: :on_request` in the another spec than the one that spawns the element might result in invoking `handle_pad_added` after `handle_playing`.

## Playing
After setup is completed, the component might now enter `:playing` playback, by invoking `handle_playing` callback.
Note: 
 - components spawned within a single `spec` will always enter `:playing` state in the same moment - it means, if setup of one of them takes longer than other, the rest will wait on the component that is the last.
 - Elements and Bins always wait with execution of `handle_playing` until their parent enters `playing` playback.
 - by default, after `handle_setup` callback the component's setup is considered as completed. But this behaviour can be changed by returning `setup: :incomplete` action from `handle_setup`. If so, to enter `playing` playback, the component mark its setup as completed by returning `setup: :complete` from another callback, e.g. `handle_info/3`.

## Processing the data (applies only to `Elements`)
After execution of `handle_playing`, Elements are now ready to process the data that flows through the pads.

### Events
The first type of the items that can be sent via Elements' pads are `events`. Handling an event takes place in `hanlde_event`. Event can be sent both upstream and downstream the direction of the pad.

### Stream formats
Stream format specifies what type of the data will be sent in `Membrane.Buffer`'s. The stream format must be sent before first `Membrane.Buffer` and is handled in `handle_stream_format`

### Start of stream
This callback (`handle_start_of_stream`) will be invoked just before handling the first `Membrane.Buffer` incoming from the specific input pad.

### Buffers
The core of the multimedia processing. `Membrane.Buffer`'s contain multimedia payload, but they also may have information about some metadata or timestamps. Handling them takes place in `handle_buffer` callback.

## After processing the data
If the element decides, that it won't send any more buffers on the specific pad, it can send `:end_of_stream` there. It will be received by the linked element in `handle_end_of_stream` callback. 
When the element receives `end_of_stream` callback, it's parent (Bin or Pipeline) will be also notified about it in `handle_element_end_of_stream` callback.

## Terminating
Usually the last callback executed within a Membrane Component is `handle_terminate_request`. By default it returns `terminate: :normal` action, which ends the lifespan of the component (with reason `:normal`).
You can change this behaviour by overriding defeault impelmentation of this callback, but remember tho return `terminate: reason` in another place! Otherwise, your Pipeline will have problems with getting termianted.

## Callbacks not strictly related to the lifecycle
Not all the callbacks are restricted to occur in specific moments in the Membrane Component lifecycle.

### Handling parent/child notification
`handle_parent_notification` and `handle_child_notification` are the 2 callbacks that can during the whole Component's lifecycle. They are responsible for handling nofications sent from respectively parent or child Component.

### Handling messages from non-Membrane processes 
There is also a `handle_info` callback in all of the Membrane Components and `handle_call` in Membrane Pipelines, that can be invoked in every moment, when the Component is alive. Their function is annalogical as in the `GenServer`.
