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

## All packages

### Media agnostic packages
| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_core`              | The core of the framework                                                       | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_core.svg)](https://hex.pm/packages/membrane_core) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_core) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_core)                                                     | |
| `membrane_common_c`          | Utilities for the native parts of Membrane                                      | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_common_c.svg)](https://hex.pm/packages/membrane_common_c) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_common_c) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_common_c)                                     | | 
| `membrane_telemetry_metrics` | Tool for generating metrics                                                     | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_telemetry_metrics.svg)](https://hex.pm/packages/membrane_telemetry_metrics) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_telemetry_metrics) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_telemetry_metrics) | |
| `membrane_opentelemetry`     | Wrapper of OpenTelemetry functions for Membrane Multimedia Framework            | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_opentelemetry.svg)](https://hex.pm/packages/membrane_opentelemetry) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_opentelemetry) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_opentelemetry) | |
| `bundlex`                    | Tool for compiling C/C++ code within Mix projects                               | [![Hex.pm](https://img.shields.io/hexpm/v/bundlex.svg)](https://hex.pm/packages/bundlex) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_opentelemetry) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/bundlex)                                                                             | |
| `unifex`                     | Tool automatically generating NIF and CNode interfaces between C/C++ and Elixir | [![Hex.pm](https://img.shields.io/hexpm/v/unifex.svg)](https://hex.pm/packages/unifex) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/unifex) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/unifex)                                                                                 | |
| `bunch`                      | Extension of Elixir standard library                                            | [![Hex.pm](https://img.shields.io/hexpm/v/bunch.svg)](https://hex.pm/packages/bunch) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/bunch) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/bunch)                                                                                     | |
| `sebex`                      | The ultimate assistant in Membrane Framework releasing & development            | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/sebex) | |
| `Beamchmark`                 | Tool for measuring BEAM performance                                             | [![Hex.pm](https://img.shields.io/hexpm/v/beamchmark.svg)](https://hex.pm/packages/beamchmark) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/beamchmark) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/beamchmark) | |

### Plugins

Membrane plugins are packages which provide the elements and bins that can be used in pipelines built with the Membrane Framework. These plugins can provide various multimedia processing capabilities and help in dealing with various formats,
codecs, protocols, containers and external APIs.

#### Media agnostic

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_file_plugin`                    | Plugin for reading and writing to files                                                | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_file_plugin.svg)](https://hex.pm/packages/membrane_file_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_file_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_file_plugin)                                                                                | |
| `membrane_udp_plugin`                     | Plugin for sending and receiving UDP streams                                           | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_udp_plugin.svg)](https://hex.pm/packages/membrane_udp_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_udp_plugin) [![![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_udp_plugin) | |
| `membrane_hackney_plugin`                 | HTTP sink and source based on Hackney library                                          | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_hackney_plugin.svg)](https://hex.pm/packages/membrane_hackney_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_hackney_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_hackney_plugin)                                                                    | |
| `membrane_scissors_plugin`                | Element for cutting off parts of the stream                                            | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_scissors_plugin.svg)](https://hex.pm/packages/membrane_scissors_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_scissors_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_scissors_plugin)                                                                | |
| `membrane_tee_plugin `                    | Plugin for splitting data from a single input to multiple outputs                      | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_tee_plugin.svg)](https://hex.pm/packages/membrane_tee_plugin ) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_tee_plugin ) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_tee_plugin)                                                                                | |
| `membrane_funnel_plugin`                  | Plugin for merging multiple input streams into a single output                         | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_funnel_plugin.svg)](https://hex.pm/packages/membrane_funnel_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_funnel_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_funnel_plugin)                                                                        | |
| `membrane_realtimer_plugin`                | Membrane element limiting playback speed to realtime, according to buffers' timestamps | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_realtimer_plugin.svg)](https://hex.pm/packages/membrane_realtimer_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_realtimer_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_realtimer_plugin)                                                            | |
| `membrane_stream_plugin`                   | Plugin for dumping and restoring a Membrane Stream to and from a binary format         | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_stream_plugin.svg)](https://hex.pm/packages/membrane_stream_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_stream_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_stream_plugin) | |
| `membrane_fake_plugin`                     | Plugin with fake sink elements that consume & drop incoming data                        | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_fake_plugin.svg)](https://hex.pm/packages/membrane_fake_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_fake_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_fake_plugin) | |
| `membrane_pcap_plugin`                     | [Experimental] Plugin for reading files in pcap format                                 | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_pcap_plugin) | |
| `membrane_live_framerate_converter_plugin` | [Third-Party] [Experimental] Plugin for producing a stable output framerate              | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/kim-company/membrane_live_framerate_converter_plugin) | |
| `membrane_node_proxy`                      | [Third-Party] [Experimental] Plugin providing a mechanism for starting and connecting sources and sinks that span Erlang nodes | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/geometerio/membrane_node_proxy) | |

#### Media network protocols & containers

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_rtp_plugin`                  | Membrane bins and elements for handling RTP and RTCP streams                                                    | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_plugin.svg)](https://hex.pm/packages/membrane_rtp_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtp_plugin)                                                                     | |
| `membrane_rtp_h264_plugin`             | RTP payloader and depayloader for H264                                                                          | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_h264_plugin.svg)](https://hex.pm/packages/membrane_rtp_h264_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_h264_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtp_h264_plugin)                                                 | |
| `membrane_rtp_vp8_plugin`              | RTP payloader and depayloader for VP8                                                                           | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_vp8_plugin.svg)](https://hex.pm/packages/membrane_rtp_vp8_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_vp8_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtp_vp8_plugin)                                                     | |
| `membrane_rtp_vp9_plugin`              | RTP payloader and depayloader for VP9                                                                           | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_rtp_vp9_plugin)                                                                                                                                                                                                                                                                                            | |
| `membrane_rtp_mpegaudio_plugin`        | RTP MPEG Audio depayloader                                                                                      | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_mpegaudio_plugin.svg)](https://hex.pm/packages/membrane_rtp_mpegaudio_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_mpegaudio_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtp_mpegaudio_plugin)                             | |
| `membrane_rtp_opus_plugin`             | RTP payloader and depayloader for OPUS audio                                                                    | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_opus_plugin.svg)](https://hex.pm/packages/membrane_rtp_opus_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_opus_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtp_opus_plugin)                                                 | |
| `membrane_rtmp_plugin`                 | Plugin for receiving, demuxing, parsing and streaming RTMP streams. Includes TCP server for handling connections| [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtmp_plugin.svg)](https://hex.pm/packages/membrane_rtmp_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtmp_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtmp_plugin)                                                 | |
| `membrane_mpegts_plugin`               | MPEG-TS demuxer                                                                                                 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mpegts_plugin.svg)](https://hex.pm/packages/membrane_mpegts_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mpegts_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_mpegts_plugin)                                                         | |
| `membrane_mp4_plugin`                  | Utilities for MP4 container parsing and serialization and elements for muxing the stream to CMAF                | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mp4_plugin.svg)](https://hex.pm/packages/membrane_mp4_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mp4_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_mp4_plugin)                                                                     | |
| `membrane_http_adaptive_stream_plugin` | Plugin generating manifests for HLS (DASH support planned)                                                      | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_http_adaptive_stream_plugin.svg)](https://hex.pm/packages/membrane_http_adaptive_stream_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_http_adaptive_stream_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_http_adaptive_stream_plugin) | |
| `membrane_matroska_plugin`             | Plugin for muxing audio and video streams to Matroska container and demuxing matroska stream to audio and video | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_matroska_plugin.svg)](https://hex.pm/packages/membrane_matroska_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_matroska_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_matroska_plugin)                                                 | |
| `membrane_flv_plugin`                  | Plugin for muxing audio and video streams to FLV format and demuxing FLV stream to audio and video              | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_flv_plugin.svg)](https://hex.pm/packages/membrane_flv_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_flv_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_flv_plugin)                                                                     | |
| `membrane_ivf_plugin`                  | Plugin for serializing and deserializng Indeo Video Format stream                                               | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ivf_plugin.svg)](https://hex.pm/packages/membrane_ivf_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ivf_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_ivf_plugin)                                                                     | |
| `membrane_ogg_plugin`                  | [Experimental] Ogg demuxer and parser | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_ogg_plugin) | |
| `membrane_quic_plugin`                  | [Experimental] Plugin containing elements for sending and receiving data over QUIC. It contains also QUIC server | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/mickel8/membrane_quic_plugin) | |
| `membrane_hls_plugin`                  | [Third-Party] [Alpha] Membrane.HLS.Source element for HTTP Live Streaming (HLS) playlist files | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/kim-company/membrane_hls_plugin) | |
| `membrane_ogg_plugin`                  | [Third-Party] [Alpha] Ogg plugin based on the libogg | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/ledhed2222/membrane_ogg_plugin)                                                                     | |

#### Audio codecs

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_aac_plugin`             | AAC parser and complementary elements for AAC codec          | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_aac_plugin.svg)](https://hex.pm/packages/membrane_aac_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_aac_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_aac_plugin)                                                 | |
| `membrane_aac_fdk_plugin`         | AAC decoder and encoder based on FDK library                 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_aac_fdk_plugin.svg)](https://hex.pm/packages/membrane_aac_fdk_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_aac_fdk_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_aac_fdk_plugin)                                 | |
| `membrane_flac_plugin`            | Parser for files in FLAC bitstream format                    | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_flac_plugin.svg)](https://hex.pm/packages/membrane_flac_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_flac_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_flac_plugin)             | |
| `membrane_mp3_lame_plugin`        | Membrane MP3 encoder based on Lame                           | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mp3_lame_plugin.svg)](https://hex.pm/packages/membrane_mp3_lame_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mp3_lame_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_mp3_lame_plugin)                             | |
| `membrane_mp3_mad_plugin`         | Membrane MP3 decoder based on MAD                            | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mp3_mad_plugin.svg)](https://hex.pm/packages/membrane_mp3_mad_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mp3_mad_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_mp3_mad_plugin)                                 | |
| `membrane_element_mpegaudioparse` | Element capable of parsing bytestream into MPEG audio frames | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_element_mpegaudioparse.svg)](https://hex.pm/packages/membrane_element_mpegaudioparse) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_element_mpegaudioparse) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-element-mpegaudioparse) | |
| `membrane_opus_plugin`            | Opus encoder, decoder and parser                             | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_opus_plugin.svg)](https://hex.pm/packages/membrane_opus_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_opus_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_opus_plugin)                                             | |
| `membrane_wav_plugin`             | WAV parser                                                   | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_wav_plugin.svg)](https://hex.pm/packages/membrane_wav_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_wav_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_wav_plugin)                                                 | |


#### Video codecs

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_h264_ffmpeg_plugin` | Membrane H264 parser, decoder and encoder based on FFmpeg and x264 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_h264_ffmpeg_plugin.svg)](https://hex.pm/packages/membrane_h264_ffmpeg_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_h264_ffmpeg_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_h264_ffmpeg_plugin) | |
| `membrane_h264_plugin`          | Pure Elixir Membrane H264 parser                                          | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_h264_plugin.svg)](https://hex.pm/packages/membrane_h264_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_h264_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_h264_plugin) | |
| `turbojpeg`                     | [Third-party] libjpeg-turbo bindings for Elixir by Binary Noggin   | [![Hex.pm](https://img.shields.io/hexpm/v/turbojpeg.svg)](https://hex.pm/packages/turbojpeg) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/turbojpeg/readme.html) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/binarynoggin/elixir-turbojpeg)                                                           | |
| `membrane_subtitle_mixer_plugin`| [Third-party] [Alpha] Plugin that uses CEA708 to merge subtitles directly in H264 packets   | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/kim-company/membrane_subtitle_mixer_plugin) | |
| `membrane_mpeg_ts_plugin`       | [Third-party] [Alpha] MPEG-TS Demuxer                                    | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/kim-company/membrane_mpeg_ts_plugin) | |


#### Raw

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_generator_plugin` | Video and audio samples generator | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_generator_plugin.svg)](https://hex.pm/packages/membrane_generator_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_generator_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_generator_plugin) | |

##### Raw audio

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_portaudio_plugin`         | Raw audio retriever and player based on PortAudio                                                            | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_portaudio_plugin.svg)](https://hex.pm/packages/membrane_portaudio_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_portaudio_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_portaudio_plugin)                                 | |
| `membrane_ffmpeg_swresample_plugin` | Plugin performing audio conversion, resampling and channel mixing, using SWResample module of FFmpeg library | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ffmpeg_swresample_plugin.svg)](https://hex.pm/packages/membrane_ffmpeg_swresample_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ffmpeg_swresample_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_ffmpeg_swresample_plugin) | |
| `membrane_audiometer_plugin`        | Elements for measuring the level of the audio stream                                                         | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_audiometer_plugin.svg)](https://hex.pm/packages/membrane_audiometer_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_audiometer_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_audiometer_plugin)                             | |
| `membrane_audio_mix_plugin`         | Elements for mixing audio streams                                                                            | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_audio_mix_plugin.svg)](https://hex.pm/packages/membrane_audio_mix_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_audio_mix_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_audio_mix_plugin)                                 | |
| `membrane_element_fade`             | [Experimental]                                                                                               | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-element-fade) | |

##### Raw video

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_sdl_plugin`                      | Membrane video player based on SDL                                                                            | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_sdl_plugin.svg)](https://hex.pm/packages/membrane_sdl_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_sdl_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_sdl_plugin)                                                                 | |
| `membrane_raw_video_parser_plugin`         | Plugin for parsing raw video streams                                                                          | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_raw_video_parser_plugin.svg)](https://hex.pm/packages/membrane_raw_video_parser_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_raw_video_parser_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_raw_video_parser_plugin)             | |
| `membrane_ffmpeg_swscale_plugin`           | Plugin for scaling raw video streams and converting raw video format                                          | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ffmpeg_swscale_plugin.svg)](https://hex.pm/packages/membrane_ffmpeg_swscale_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ffmpeg_swscale_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_ffmpeg_swscale_plugin)                     | |
| `membrane_framerate_converter_plugin`      | Plugin for adjusting the framerate of raw video stream                                                        | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_framerate_converter_plugin.svg)](https://hex.pm/packages/membrane_framerate_converter_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_framerate_converter_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_framerate_converter_plugin) | |
| `membrane_video_merger_plugin`             | Plugin for cutting and merging raw video streams                                                              | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_video_merger_plugin.svg)](https://hex.pm/packages/membrane_video_merger_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_video_merger_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_video_merger_plugin)                             | |
| `membrane_camera_capture_plugin`           | This plugin can be used to capture video stream from an input device                                          | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_camera_capture_plugin.svg)](https://hex.pm/packages/membrane_camera_capture_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_camera_capture_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_camera_capture_plugin)                     | |
| `membrane_ffmpeg_video_filter_plugin`      | This plugin contains elements providing video filters based on ffmpeg video filter feature                   | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ffmpeg_video_filter_plugin.svg)](https://hex.pm/packages/membrane_ffmpeg_video_filter_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ffmpeg_video_filter_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_ffmpeg_video_filter_plugin)                     | |
| `membrane_video_compositor_plugin`         | [Alpha] WGPU based plugin for composing, transforming and editing multiple raw videos in real time | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_video_compositor_plugin)                     | |
| `membrane_video_mixer_plugin`        | [Experimental] [Third-Party] Element which mixes multiple video inputs to a single output using ffmpeg filters | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_video_mixer_plugin.svg)](https://hex.pm/packages/membrane_video_mixer_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/kim-company/membrane_video_mixer_plugin) | |

#### External APIs

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_element_gcloud_speech_to_text` | Plugin providing speech recognition via Google Cloud Speech-to-Text API  | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_element_gcloud_speech_to_text.svg)](https://hex.pm/packages/membrane_element_gcloud_speech_to_text) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_element_gcloud_speech_to_text) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_element_gcloud_speech_to_text) | |
| `membrane_element_ibm_speech_to_text`    | Plugin providing speech recognition via IBM Cloud Speech-to-Text service | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_element_ibm_speech_to_text.svg)](https://hex.pm/packages/membrane_element_ibm_speech_to_text) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_element_ibm_speech_to_text) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_element_ibm_speech_to_text)             | |
| `membrane_s3_plugin`                     | [Third-Party] Plugin providing sink that writes to Amazon S3 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_s3_plugin.svg)](https://hex.pm/packages/membrane_s3_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_s3_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/YuzuTen/membrane_s3_plugin)             | |
| `membrane_transcription`                  | [Third-Party] [Experimental] Plugin based on Whisper allowing creating transcriptions | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/lawik/membrane_transcription)             | |
| `xturn_membrane`                          | [Third-Party] [Experimental] Experimental Membrane source / sink for XTurn | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/xirsys/xturn-membrane)             | |


### Formats

| Package | Description | Links |
|---|---|---|
| `membrane_raw_audio_format` | Raw audio format definition                    | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_raw_audio_format.svg)](https://hex.pm/packages/membrane_raw_audio_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_raw_audio_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_raw_audio_format)         |
| `membrane_raw_video_format` | Raw video format definition                    | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_raw_video_format.svg)](https://hex.pm/packages/membrane_raw_video_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_raw_video_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_raw_video_format) |
| `membrane_aac_format`       | Advanced Audio Codec format definition         | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_aac_format.svg)](https://hex.pm/packages/membrane_aac_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_aac_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_aac_format)                         |
| `membrane_mp4_format`       | MPEG-4 container format definition             | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mp4_format.svg)](https://hex.pm/packages/membrane_mp4_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mp4_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_mp4_format)                         |
| `membrane_opus_format`      | Opus audio format definition                   | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_opus_format.svg)](https://hex.pm/packages/membrane_opus_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_opus_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_opus_format)                     |
| `membrane_rtp_format`       | Real-time Transport Protocol format definition | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_format.svg)](https://hex.pm/packages/membrane_rtp_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtp_format)                         |
| `membrane_mpegaudio_format` | MPEG audio format definition                   | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mpegaudio_format.svg)](https://hex.pm/packages/membrane_mpegaudio_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mpegaudio_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_mpegaudio_format) |
| `membrane_h264_format`      | H264 video format definition                   | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_h264_format.svg)](https://hex.pm/packages/membrane_h264_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_h264_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_h264_format)                     |
| `membrane_cmaf_format`      | CMAF definition                                | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_cmaf_format.svg)](https://hex.pm/packages/membrane_cmaf_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_cmaf_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_cmaf_format)                     |
| `membrane_matroska_format`  | Matroska format definition                     | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_matroska_format.svg)](https://hex.pm/packages/membrane_matroska_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_matroska_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_matroska_format)     |
| `membrane_vp8_format`       | VP8 Format Description                         | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_vp8_format.svg)](https://hex.pm/packages/membrane_vp8_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_vp8_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_vp8_format)     |
| `membrane_vp9_format`       | VP9 Format Description                         | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_vp9_format.svg)](https://hex.pm/packages/membrane_vp9_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_vp9_format) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_vp9_format)     |


### Apps, protocols & plugins' utilities

| Package | Description | Links | Used By |
|---|---|---|---|
| `ex_sdp`                       | Parser and serializer for Session Description Protocol                                                                              | [![Hex.pm](https://img.shields.io/hexpm/v/ex_sdp.svg)](https://hex.pm/packages/ex_sdp) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_sdp) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/ex_sdp)                                                        | |
| `ex_libnice`                   | Libnice-based Interactive Connectivity Establishment (ICE) protocol support for Elixir                                              | [![Hex.pm](https://img.shields.io/hexpm/v/ex_libnice.svg)](https://hex.pm/packages/ex_libnice) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_libnice) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/ex_libnice)                                        | |
| `ex_libsrtp`                   | Elixir bindings for [libsrtp](https://github.com/cisco/libsrtp)                                                                     | [![Hex.pm](https://img.shields.io/hexpm/v/ex_libsrtp.svg)](https://hex.pm/packages/ex_libsrtp) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_libsrtp) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/ex_libsrtp)                                        | |
| `ex_dtls`                      | DTLS and DTLS-SRTP handshake library for Elixir, based on OpenSSL                                                                   | [![Hex.pm](https://img.shields.io/hexpm/v/ex_dtls.svg)](https://hex.pm/packages/ex_dtls) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_dtls) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/ex_dtls)                                                    | |
| `membrane_rtsp`                | RTSP client for Elixir                                                                                                              | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtsp.svg)](https://hex.pm/packages/membrane_rtsp) [![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtsp/) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtsp)                       | |
| `membrane_common_audiomix`     | [Experimental]                                                                                                                      | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-common-audiomix)                                                                                                                                                                                                                               | |
| `membrane_ffmpeg_generator`     | FFmpeg video and audio generator for tests, benchmarks and demos.                                                                                                                                                                 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ffmpeg_generator.svg)](https://hex.pm/packages/membrane_ffmpeg_generator) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ffmpeg_generator/) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_ffmpeg_generator) | |
| `membrane_telemetry_dashboard` | Introduction to integrating `membrane_timescaledb_reporter` repository with `membrane_dashboard` to monitor your pipeline behaviour | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_telemetry_dashboard) | |
| `membrane_webrtc_server`       | Signalling server for WebRTC                                                                                                         | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_webrtc_server.svg)](https://hex.pm/packages/membrane_webrtc_server) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_webrtc_server) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/webrtc-server) | |


### Jellyfish

Jellyfish is a GitHub organization containing Membrane WebRTC-related repositories, focusing on creating a standalone media server.

#### Plugins
| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_rtc_engine`                    | RTC Engine and its client library                                                 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtc_engine.svg)](https://hex.pm/packages/membrane_rtc_engine) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtc_engine) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtc_engine)             | |
| `membrane_webrtc_plugin`                 | [Alpha] Plugin for sending and receiving media with WebRTC                        | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_webrtc_plugin.svg)](https://hex.pm/packages/membrane_webrtc_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_webrtc_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_webrtc_plugin) | |
| `membrane_ice_plugin`                    | Plugin for ICE protocol                                                           | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ice_plugin.svg)](https://hex.pm/packages/membrane_ice_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ice_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_ice_plugin)                                                                     | |

#### Libraries
| Package | Description | Links | Used By |
|---|---|---|---|
| `fake_turn`                              | STUN and TURN library for Erlang / Elixir                                            | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/fake_turn) | |
| `membrane_rtc_engine_timescaledb`        | Functions which allow storing `Membrane.RTC.Engine` metrics reports in a database    | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtc_engine_timescaledb.svg)](https://hex.pm/packages/membrane_rtc_engine_timescaledb) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtc_engine_timescaledb) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_rtc_engine_timescaledb) | |
| `jellyfish `                             | [In progress] Standalone media server                                                | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/jellyfish-dev/jellyfish) | |


#### RTC Engine clients

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane-webrtc-js` | JS/TS client library for Membrane RTC Engine | [![NPM version](https://img.shields.io/npm/v/@membraneframework/membrane-webrtc-js)](https://www.npmjs.com/package/@membraneframework/membrane-webrtc-js) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-webrtc-js/) | |
| `membrane-webrtc-ios` | Membrane WebRTC client compatible with Membrane RTC Engine | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-webrtc-ios) | |
| `membrane-webrtc-android` | Membrane WebRTC client compatible with Membrane RTC Engine | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-webrtc-android) | |
| `react-native-membrane-webrtc` | React Native wrapper for `membrane-webrtc-ios` and `membrane-webrtc-android` | [![NPM version](https://img.shields.io/npm/v/@membraneframework/react-native-membrane-webrtc)](https://www.npmjs.com/package/@membraneframework/react-native-membrane-webrtc)  [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/react-native-membrane-webrtc) | |

#### Book
| Package | Description | Links |
|---|---|---|
| `Jellybook`                        | Theoretical concepts behind general purpose media server. | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/jellyfish-dev/book)               |


### RTC Engine based applications

| Package | Description | Links | Used By |
|---|---|---|---|
| `membrane_videoroom`           | Video conferencing platform using WebRTC                                                       | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_videoroom/) | |
| `membrane_live`                | [Alpha] Webinar app in React, Phoenix and Membrane                                             | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_live/) | |


### Tutorials

| Package | Description | Links |
|---|---|---|
| `membrane_tutorials`               | Repository with tutorials text                         | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_tutorials)               |
| `membrane_basic_pipeline_tutorial` | Code used in the comprehensive basic pipeline tutorial | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_basic_pipeline_tutorial) |
| `membrane_videoroom_tutorial`      | Code used in the videroom tutorial                     | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_videoroom_tutorial)      |
| `membrane_webrtc_tutorial`         | Code used in the webrtc tutorial                       | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_webrtc_tutorial)    |

### No longer mantained

| Package | Description | Links |
|---|---|---|
| `membrane_libnice_plugin`           | Replaced by `membrane_ice_plugin`                                                | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_libnice_plugin.svg)](https://hex.pm/packages/membrane_libnice_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_libnice_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_libnice_plugin) |
| `membrane_element_httpoison`        | Replaced by `membrane_element_hackney`                                           | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_element_httpoison.svg)](https://hex.pm/packages/membrane_element_httpoison) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_libnice_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_element_httpoison) |
| `membrane_dtls_plugin`              | DTLS and DTLS-SRTP handshake implementation for Membrane ICE plugin              | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_dtls_plugin.svg)](https://hex.pm/packages/membrane_dtls_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_element_httpoison) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_element_httpoison)                  |
| `membrane_loggers`                  | Replaced by the `Membrane.Logger` in Membrane Core                               | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_loggers.svg)](https://hex.pm/packages/membrane_loggers) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_loggers) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane_loggers)                  |
| `membrane_caps_audio_flac`          | [Suspended] FLAC audio format definition                                         | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_caps_audio_flac.svg)](https://hex.pm/packages/membrane_caps_audio_flac) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_caps_audio_flac) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-caps-audio-flac)     |
| `membrane_remote_stream_format`     | Content of this package has been moved to `membrane_core`                        | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_remote_stream_format.svg)](https://hex.pm/packages/membrane_remote_stream_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_remote_stream_format)                   |
| `membrane_element_rtp_jitter_buffer`| Package has become part of `membrane_rtp_plugin`                                 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_element_rtp_jitter_buffer.svg)](https://hex.pm/packages/membrane_element_rtp_jitter_buffer) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_element_rtp_jitter_buffer)                   |
| `membrane_bin_rtp`                  | Package has become part of `membrane_rtp_plugin`                                 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_bin_rtp.svg)](https://hex.pm/packages/membrane_bin_rtp) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_bin_rtp)                   |
| `membrane_element_icecast`          | [Experimental] Element capable of sending a stream into Icecast streaming server | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-element-icecast)                                                                                                                                                                                                                                                 |
| `membrane_element_live_audiomixer`  | Simple mixer that combines audio from different sources                          | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-element-live-audiomixer)                                                                                                                                                                                                                                         |
| `membrane_element_msdk_h264`        | [Experimental] Hardware-accelerated H.264 encoder based on IntelMediaSDK         | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-element-msdk-h264)                                                                                                                                                                                                                                               |
| `membrane_rtp_aac_plugin`           | [Alpha] RTP AAC depayloader                                                      | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_aac_plugin.svg)](https://hex.pm/packages/membrane_rtp_aac_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_aac_plugin) [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework-labs/membrane_rtp_aac_plugin) |
| `membrane_element_flac_encoder`     | [Suspended]                                                                      | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-element-flac-encoder)                                                                                                                                                                                                                                            |
| `membrane_protocol_icecast`         | [Suspended]                                                                      | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-protocol-icecast)                                                                                                                                                                                                                                                |
| `membrane_server_icecast`           | [Suspended]                                                                      | [![GitHub](https://api.iconify.design/octicon:logo-github-16.svg?color=gray&height=20)](https://github.com/membraneframework/membrane-server-icecast) |

## Copyright and License

Copyright 2018, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
