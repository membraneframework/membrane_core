# Timestamps - the stamps in time

In a nutshell, timestamps determine when a given event occurred in time. For
example when you take a photo with your phone, the exact time and date the photo
is taken is recorded - it's a timestamp. When dealing with media we also need a
way to tell when different things need to happen. In Membrane we use two most
common types of timestamps:

* PTS (Presentation Time Stamp) - determines when the media should be
  displayed.
* DTS (Decoding Time Stamp) - information for the decoder when the media should
  be decoded.

## Time in Membrane

We know that timestamps represent the time of occurrence of an event, but these
concepts are pretty abstract. We need to somehow represent them in the context
of our framework. To represent time - durations, latencies, timestamps, - we
use terms of type `t:Membrane.Time.t/0`:

* To create a term representing some amount of time, we use
  `Membrane.Time.<unit>/0` and `Membrane.Time.<unit>s/1` functions. For example to
  create a term representing three seconds, we call `Membrane.Time.seconds(3)`.
* To read the amount of time represented, we can use `Membrane.Time.as_<unit>/2`
  functions. For example, to get an amount of milliseconds represented by a time,
  we call `Membrane.Time.as_milliseconds(some_time)`

## Carriers of timestamps

We now have a way to represent timestamps, but to be useful they have to refer
to something, an event of some sort. As you probably know, media streams in
Membrane are sent between elements packaged in
[Buffers](`t:Membrane.Buffer.t/0`). As we can see in the specification, a buffer
is a struct with 4 fields:

* `:payload` - data contained in the buffer
* `:pts` and `:dts` - timestamps assigned to the buffer
* `:metadata` - metadata describing the contents of the buffer

Buffers often correspond to some units which the stream is composed of, for
example video frames in raw video streams or RTP packets in RTP streams.
These units are the perfect fits to have timestamps assigned to them - and in
most cases they do. For example, a PTS assigned to a buffer containing a
raw video frame determines then the frame should be displayed.
