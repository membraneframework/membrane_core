# Everything about pads

When developing intuition about the structure of pipelines pads are
something that can't be ignored. If you think about elements and bins as some
sort of containers or boxes in which processing happens, then pads are the parts
that with these containers are connected with. There are some constraints
regarding pads:

* A pad of one element can only connect to a single pad of other element and
only once two pads are connected communication through them can happen.
* One pad needs to be an input pad, and the other an output pad.
* The accepted stream formats of the pads need to match.

When looking at the insides of elements, the pads are their main way to
communicate with other elements in the pipeline. When an element receives
something from another one (e.g. a buffer or stream format), it receives it
from a pad. The reference to this pad is then also available as an argument
of the callback that handles the received thing. For example an invocation
of the [following callback](`c:Membrane.Element.WithInputPads.handle_buffer/4`)
would mean that a buffer `buffer` has arrived on a pad `some_pad`:

```elixir
@impl true
def handle_buffer(some_pad, buffer, context, state) do 
  ...             ^^^^^^^^
end
```

When an element wants to send something to another element in the
pipeline, most likely it should send it on a pad that's connected to it. It
can do that by using the pad reference in actions that send things, for example
returning the following [buffer action](`t:Membrane.Element.Action.buffer/0`)
from a callback would mean that a buffer `buffer` will be sent on a pad `some_pad`:

```elixir
@impl true
def some_callback(...) do
  ...
  {[buffer: {some_pad, buffer}], state}
end          ^^^^^^^^
```

## Defining pads

To define what pads an element will have and how they'll behave we use
[`def_input_pad/2`](`Membrane.Element.WithInputPads.def_input_pad/2`)
and [`def_output_pad/2`](`Membrane.Element.WithOutputPads.def_output_pad/2`) macros.
Input pads can only be defined for Sinks, Filters and Endpoints, and output
pads can only be defined for Sources, Filters and Endpoints.
The first argument for these macros is a name, which then will be used to
identify the pads. The second argument is a `t:Membrane.Pad.element_spec/0`
keyword list, which is used to define how this pad will work. An option we'll
now focus on is [`availability`](`t:Membrane.Pad.availability/0`), which
determines if the pad is _static_ or _dynamic_.

### Static pads

Static pads are pretty straightforward - when a static pad is defined there
will always be exactly one instance of this pad and it's referenced by it's
name.

#### File Source Example

Example of an element with only static pads is a [File Source](https://hexdocs.pm/membrane_file_plugin/Membrane.File.Source.html).
This element reads contents of a file and sends them in batches through a static
output pad. The content of the buffers sent by this element is unknown - the file
that's being read can contain anything - so this pad has `:accepted_format` set to
`%RemoteStream{type: :bytestream}`. That means that any stream format that
matches on this struct can be sent on the output pad and this fact has to be
accounted for when connecting an element after the source.

A pipeline spec with a file source passing buffers to a MP4 demuxer could look
like this:

```elixir
@impl true
def handle_init(_context, state) do
  spec = 
    child(:source, %Membrane.File.Source{location: "my_file.mp4"})
    |> via_out(:output)
    |> via_in(:input)
    |> child(:mp4_demuxer, Membrane.MP4.ISOM.Demuxer)

  {[spec: spec], state}
end
```

This spec will connect a pad named `:output` of the source to a pad named
`:input` of the demuxer. However this can be shortened - if an output pad is
called `:output` or an input pad is called `:input`, their respective
[`via_in/3`](`Membrane.ChildrenSpec.via_in/3`) and
[`via_out/3`](`Membrane.ChildrenSpec.via_out/3`) calls can be omitted and
Membrane will automatically recognize and connect them:

```elixir
@impl true
def handle_init(_context, state) do
  spec = 
    child(:source, %Membrane.File.Source{location: "my_file.mp4"})
    |> child(:mp4_demuxer, Membrane.MP4.ISOM.Demuxer)

  {[spec: spec], state}
end
```

### Dynamic pads

Dynamic pads are a bit more complex. They're used when the amount of pads of
given type is variable - dependent on the processed stream or external factors.
The creation of these pads is controlled by the parent of the element - if a
[`:spec`](`t:Membrane.Pipeline.Action.spec/0`) action linking the dynamic pad is
being executed, then the pad is created dynamically and the element needs to
handle this, in most cases with
[`handle_pad_added/3`](`c:Membrane.Element.Base.handle_pad_added/3`).

Another thing that's different are the pad references. The pad's name can't just
be used as the pad's reference, because it wouldn't be unique. Dynamic pads are
identified by [`Pad.ref/2`](`Membrane.Pad.ref/2`), that takes the pad's
name and some unique reference as arguments. The result is a unique pad reference
that is also associated with a given pad's specification through it's name.

#### MP4 Demuxer Example

An example of an element using dynamic pads is an
[MP4 Demuxer](https://hexdocs.pm/membrane_mp4_plugin/Membrane.MP4.Demuxer.ISOM.html).
This element has a input pad, from which it receives contents of a MP4
container, and output pads, on which it'll send the different tracks
that were in the container. The input pad can be static, however MP4 containers can
have different numbers and kinds of tracks, so the output pad needs to be dynamic.

We'll consider the case when we don't have any prior information about the
tracks in this MP4 container. Because of this, the parent pipeline or bin of this
demuxer won't initially know how many pads should be connected. To solve this
problem the demuxer will identify the tracks in the incoming stream and send a
message to it's parent in the form of
[`{:new_tracks, [{track_id :: integer(), content :: struct()}]}`](https://hexdocs.pm/membrane_mp4_plugin/Membrane.MP4.Demuxer.ISOM.html#t:new_tracks_t/0).
The list contains a list of tuples corresponding to tracks, where the first
element is a track id and will be used to identify corresponding pad,
and the second a stream format contained in the track.

Initially the parent will only create the elements before and including the
demuxer:

```elixir
@impl true
def handle_init(_context, state) do
  spec = 
    child(:source, %Membrane.File.Source{location: "my_file.mp4"})
    |> child(:mp4_demuxer, Membrane.MP4.ISOM.Demuxer)

  {[spec: spec], state}
end
```

The source will start providing the demuxer the MP4 container content,
from which the demuxer will identify tracks and notify it's parent
about them. The parent now has to connect an output pad of the demuxer for each
track received, which can look like this:

```elixir
@impl true
def handle_child_notification({:new_tracks, tracks}, :mp4_demuxer, _context, state) do
  spec = 
    Enum.map(tracks, fn {id, format} ->
        get_child(:mp4_demuxer)
        |> via_out(Pad.ref(:output, id))
        |> ...
      end)

  {[spec: spec], state}
end
```

The elements that the output pads will be linked to should be based on what stream
format is in `format` variable - different formats require different approaches.

After this spec is returned, the demuxer will now have the
[`handle_pad_added/3`](`c:Membrane.Element.Base.handle_pad_added/3`) callback
called for each new connected pad with pad reference of
`Pad.ref(:output, track_id)`. It will now know that these pads are connected and
ready to pass buffers forward.
