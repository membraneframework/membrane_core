# Membrane Framework

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_core.svg)](https://hex.pm/packages/membrane_core)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_core/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_core.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_core)

### Let's meet on 13th October at [RTC.ON](https://rtcon.live) - the first conference about Membrane & multimedia!
### Learn more at [rtcon.live](https://rtcon.live)

---

Multimedia processing framework that focuses on reliability, concurrency and scalability.

Membrane is a versatile multimedia streaming & processing framework. You can use it to build a media server of your need, that can:
- stream via WebRTC, RTSP, RTMP, HLS, HTTP and other protocols,
- transcode, mix and apply custom processing of video & audio,
- accept and generate / record to MP4, MKV, FLV and other containers,
- handle dynamically connecting and disconnecting streams,
- seamlessly scale and recover from errors,
- do whatever you imagine if you implement it yourself :D Membrane makes it easy to plug in your code at almost any point of processing.

The abbreviations above don't ring any bells? Visit [membrane.stream/learn](membrane.stream/learn) and let Membrane introduce you to the multimedia world!

Want a generic media server, instead of building a custom one? Try [Jellyfish](https://github.com/jellyfish-dev/jellyfish) - it's built on top of Membrane and provides many of its features via simple, WebSocket API. We'll soon [provide it as a SAAS](https://membrane.stream/cloud) too.

If you have questions or need consulting, we're for you at our [Discord](https://discord.gg/nwnfVSY), [forum](https://elixirforum.com/c/elixir-framework-forums/membrane-forum/), [GitHub discussions](https://github.com/orgs/membraneframework/discussions), [X (Twitter)](https://twitter.com/ElixirMembrane) and via [e-mail](mailto:info@membraneframework.org).

Membrane is maintained by [Software Mansion](swmansion.com).

## Quick start

```elixir
Mix.install([
  :membrane_hackney_plugin,
  :membrane_mp3_mad_plugin,
  :membrane_portaudio_plugin,
])

import Membrane.ChildrenSpec
alias Membrane.RCPipeline

mp3_url = "https://raw.githubusercontent.com/membraneframework/membrane_demo/master/simple_pipeline/sample.mp3"

pipeline = RCPipeline.start_link!()

RCPipeline.exec_actions(pipeline, spec:
  child(%Membrane.Hackney.Source{location: mp3_url, hackney_opts:[follow_redirect: true]})
  |> child(Membrane.MP3.MAD.Decoder)
  |> child(Membrane.PortAudio.Sink)
)
```

This is an [Elixir](elixir-lang.org) snippet, that streams an mp3 via HTTP and plays it on your speaker. To run it, do the following:
- Install libmad and portaudio. Membrane uses these libs to decode the mp3 and to access your speaker, respectively. You can use these commands:
  - On Mac OS: `brew install libmad portaudio pkg-config`
  - On Debian: `apt install libmad0-dev portaudio19-dev`

- Option 1: Click the button below:

  [![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fmembraneframework%2F.github%2Fblob%2Freadme%2Fprofile%2Fquick_start.livemd)

  It will install [Livebook](livebook.dev), an interactive notebook similar to Jupyter, and it'll open the snippet in there for you. Then just click the 'run' button in there.

- Option 2: If you don't want to use Livebook, you can [install Elixir](https://elixir-lang.org/install.html), type `iex` to run interactive shell and paste the snippet there.

After that, you should hear music playing on your speaker :tada:

To learn step-by-step what exactly happens here, follow [this tutorial](https://membrane.stream/learn/get_started_with_membrane).

## Learning

The best place to learn Membrane is the [membrane.stream/learn](membrane.stream/learn) website and the [membrane_demo](github.com/membraneframework/membrane_demo) repository. Try them out, then hack something exciting!

## Usage

Membrane API is mostly based on media processing pipelines. To create one, create an Elixir project, script or livebook and add some plugins to dependencies. Plugins provide elements that you can use in your pipeline, as demonstrated in the 'Quick start' section above.

**Plugins**

Each plugin lives in a `membrane_X_plugin` repository, where X can be a protocol, codec, container or functionality, for example [mebrane_opus_plugin](github.com/membraneframework/membrane_opus_plugin). Plugins wrapping a tool or library are named `membrane_X_LIBRARYNAME_plugin` or just `membrane_LIBRARYNAME_plugin`, like [membrane_mp3_mad_plugin](github.com/membraneframework/membrane_mp3_mad_plugin). Plugins are published on [hex.pm](hex.pm), for example [hex.pm/packages/membrane_opus_plugin](hex.pm/pakcages/membrane_opus_plugin) and docs are at [hexdocs](hexdocs.pm), like [hexdocs.pm/membrane_opus_plugin](hexdocs.pm/membrane_opus_plugin). Some plugins require native libraries installed in your OS. Those requirements, along with usage examples are outlined in each plugin's readme.

**Formats**

Apart from plugins, Membrane has stream formats, which live in `membrane_X_format` repositories, where X is usually a codec or container, for example [mebrane_opus_format](github.com/membraneframework/mebrane_opus_format). Stream formats are published the same way as packages and are used by elements to define what kind of stream can be sent or received. They also provide utility functions to deal with a given codec/container.

**Core**

The API for creating pipelines (and custom elements too) is provided by [membrane_core](github.com/membraneframework/membrane_core). To install it, add the following line to your `deps` in `mix.exs` and run `mix deps.get`

```elixir
{:membrane_core, "~> 0.12.0"}
```

Or, if you'd like to try the latest release candidate, use this version:

```elixir
{:membrane_core, "~> 1.0.0-rc0"}
```

**Standalone libraries**

Last but not least, Membrane provides tools and libraries that can be used standalone and don't depend on the membrane_core, for example [video_compositor](github.com/membraneframework/video_compositor), [ex_sdp](github.com/membraneframework/ex_sdp) or [unifex](github.com/membraneframework/unifex).

## Goals

The main goals of Membrane are:
- To make work with multimedia a more pleasant experience than it is now.
- To provide a welcoming ecosystem for learning multimedia development.
- To power resilient, maintainable and scalable systems.

## Elixir language

We chose Elixir for Membrane because it's a modern, high-level, easy-to-learn language, that lets us rapidly develop media solutions. Elixir's main selling points are built-in parallelism and fault-tolerance features, so we can build scalable systems that are self-healing. It also runs on the battle-tested BEAM VM, that's been widely used and actively developed since the '80s. When we need the performance of a low-level language, we delegate to Rust or C.

If you don't know Elixir, try [this tutorial](https://elixir-lang.org/getting-started) - it shouldn't take long and you'll know more than enough to get started with Membrane.

## Contributing

We welcome everyone to contribute to Membrane. Here are some ways to contribute:
- Spread the word about Membrane! Even though multimedia are present everywhere today, media dev is still quite niche. Let it be no longer!
- Create learning materials. We try our best but can cover only a limited number of Membrane use cases.
- Improve docs. We know it's not the most exciting part, but if you had a hard time understanding the docs, you're the best person to fix them ;)
- Contribute code - plugins, features and bug fixes. It's best to contact us before, so we can provide our help & assistance, and agree on important matters. For details see the [contribution guide](CONTRIBUTING.md)

## Support and questions

If you have any problems with Membrane Framework feel free to contact us via [Discord](https://discord.gg/nwnfVSY), [forum](https://elixirforum.com/c/elixir-framework-forums/membrane-forum/), [GitHub discussions](https://github.com/orgs/membraneframework/discussions), [X (Twitter)](https://twitter.com/ElixirMembrane) or [e-mail](mailto:info@membraneframework.org).

## Copyright and License

Copyright 2018, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
