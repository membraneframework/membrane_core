# Membrane Framework

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_core.svg)](https://hex.pm/packages/membrane_core)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_core/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_core.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_core)

### []() Let's meet on 13th October at [RTC.ON](https://rtcon.live) - the first conference about Membrane & multimedia!
### []() Learn more at [rtcon.live](https://rtcon.live)

---

Membrane is a versatile multimedia streaming & processing framework. You can use it to build a media server of your need, that can:
- stream via WebRTC, RTSP, RTMP, HLS, HTTP and other protocols,
- transcode, mix and apply custom processing of video & audio,
- accept and generate / record to MP4, MKV, FLV and other containers,
- handle dynamically connecting and disconnecting streams,
- seamlessly scale and recover from errors,
- do whatever you imagine if you implement it yourself :D Membrane makes it easy to plug in your code at almost any point of processing.

The abbreviations above don't ring any bells? Visit [membrane.stream/learn](https://membrane.stream/learn) and let Membrane introduce you to the multimedia world!

Want a generic media server, instead of building a custom one? Try [Jellyfish](https://github.com/jellyfish-dev/jellyfish) - it's built on top of Membrane and provides many of its features via simple, WebSocket API. We'll soon [provide it as a SAAS](https://membrane.stream/cloud) too.

If you have questions or need consulting, we're for you at our [Discord](https://discord.gg/nwnfVSY), [forum](https://elixirforum.com/c/elixir-framework-forums/membrane-forum/), [GitHub discussions](https://github.com/orgs/membraneframework/discussions), [X (Twitter)](https://twitter.com/ElixirMembrane) and via [e-mail](mailto:info@membraneframework.org).

You can also [follow Membrane on X (Twitter)](https://twitter.com/ElixirMembrane) or [join our Discord](https://discord.gg/nwnfVSY) to be up to date and get involved in the community.

Membrane is maintained by [Software Mansion](swmansion.com).

## Quick start

```elixir
Mix.install([
  :membrane_hackney_plugin,
  :membrane_mp3_mad_plugin,
  :membrane_portaudio_plugin,
])

defmodule MyPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, mp3_url) do
    spec =
      child(%Membrane.Hackney.Source{
        location: mp3_url, hackney_opts: [follow_redirect: true]
      })
      |> child(Membrane.MP3.MAD.Decoder)
      |> child(Membrane.PortAudio.Sink)

    {[spec: spec], %{}}
  end
end

mp3_url = "https://raw.githubusercontent.com/membraneframework/membrane_demo/master/simple_pipeline/sample.mp3"

Membrane.Pipeline.start_link(MyPipeline, mp3_url)
```

This is an [Elixir](elixir-lang.org) snippet, that streams an mp3 via HTTP and plays it on your speaker. Here's how to run it:
- Install [libmad](https://github.com/markjeee/libmad) and [portaudio](https://github.com/PortAudio/portaudio). Membrane uses these libs to decode the mp3 and to access your speaker, respectively. You can use these commands:
  - On Mac OS: `brew install libmad portaudio pkg-config`
  - On Debian: `apt install libmad0-dev portaudio19-dev`

- Option 1: Click the button below:

  [![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fmembraneframework%2Fmembrane_core%2Fblob%2Freadme%2Fexample.livemd)

  It will install [Livebook](livebook.dev), an interactive notebook similar to Jupyter, and it'll open the snippet in there for you. Then just click the 'run' button in there.

- Option 2: If you don't want to use Livebook, you can [install Elixir](https://elixir-lang.org/install.html), type `iex` to run interactive shell and paste the snippet there.

After that, you should hear music playing on your speaker :tada:

To learn step-by-step what exactly happens here, follow [this tutorial](https://membrane.stream/learn/get_started_with_membrane).

## Learning

The best place to learn Membrane is the [membrane.stream/learn](https://membrane.stream/learn) website and the [membrane_demo](https://github.com/membraneframework/membrane_demo) repository. Try them out, then hack something exciting!

## Structure of the framework

The most basic media processing entities of Membrane are `Element`s. An element might be able, for example, to mux incoming audio and video streams into MP4, or play raw audio using your sound card. You can create elements yourself, or choose from the ones provided by the framework.

Elements can be organized into a pipeline - a sequence of linked elements that perform a specific task. For example, a pipeline might receive an incoming RTSP stream from a webcam and convert it to an HLS stream, or act as a selective forwarding unit (SFU) to implement your own videoconferencing room. The [Quick start](#quick-start) section above shows how to create a simple pipeline.

### Membrane packages

To embrace modularity, Membrane is delivered to you in multiple packages, including plugins, formats, core and standalone libraries. The complete list of all the Membrane packages maintained by the Membrane team is available [here](#Membrane-packages).

**Plugins**

Plugins provide elements that you can use in your pipeline. Each plugin lives in a `membrane_X_plugin` repository, where X can be a protocol, codec, container or functionality, for example [mebrane_opus_plugin](https://github.com/membraneframework/membrane_opus_plugin). Plugins wrapping a tool or library are named `membrane_X_LIBRARYNAME_plugin` or just `membrane_LIBRARYNAME_plugin`, like [membrane_mp3_mad_plugin](https://github.com/membraneframework/membrane_mp3_mad_plugin). Plugins are published on [hex.pm](https://hex.pm), for example [hex.pm/packages/membrane_opus_plugin](https://hex.pm/pakcages/membrane_opus_plugin) and docs are at [hexdocs](https://hexdocs.pm), like [hexdocs.pm/membrane_opus_plugin](https://hexdocs.pm/membrane_opus_plugin). Some plugins require native libraries installed in your OS. Those requirements, along with usage examples are outlined in each plugin's readme.

**Formats**

Apart from plugins, Membrane has stream formats, which live in `membrane_X_format` repositories, where X is usually a codec or container, for example [mebrane_opus_format](https://github.com/membraneframework/mebrane_opus_format). Stream formats are published the same way as packages and are used by elements to define what kind of stream can be sent or received. They also provide utility functions to deal with a given codec/container.

**Core**

The API for creating pipelines (and custom elements too) is provided by [membrane_core](https://github.com/membraneframework/membrane_core). To install it, add the following line to your `deps` in `mix.exs` and run `mix deps.get`

```elixir
{:membrane_core, "~> 0.12.9"}
```

Or, if you'd like to try the latest release candidate, use this version:

```elixir
{:membrane_core, "~> 1.0.0-rc0"}
```

**Standalone libraries**

Last but not least, Membrane provides tools and libraries that can be used standalone and don't depend on the membrane_core, for example [video_compositor](https://github.com/membraneframework/video_compositor), [ex_sdp](https://github.com/membraneframework/ex_sdp) or [unifex](https://github.com/membraneframework/unifex).

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
- Contribute code - plugins, features and bug fixes. It's best to contact us before, so we can provide our help & assistance, and agree on important matters. For details see the [contribution guide](CONTRIBUTING.md).

## Support and questions

If you have any questions regarding Membrane Framework or need consulting, feel free to contact us via [Discord](https://discord.gg/nwnfVSY), [forum](https://elixirforum.com/c/elixir-framework-forums/membrane-forum/), [GitHub discussions](https://github.com/orgs/membraneframework/discussions), [X (Twitter)](https://twitter.com/ElixirMembrane) or [e-mail](mailto:info@membraneframework.org).

## All packages

<!-- packages-list-start -->
<!-- Generated code, do not edit. See `update_packages_list.exs`. -->


### General
| Package | Description | Links |
| --- | --- | --- |
| [membrane_core](https://github.com/membraneframework/membrane_core) | The core of the Membrane Framework, advanced multimedia processing framework | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_core.svg)](https://hex.pm/api/packages/membrane_core) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_core/) |
| [membrane_rtc_engine](https://github.com/jellyfish-dev/membrane_rtc_engine) | [Maintainer: [jellyfish-dev](https://github.com/jellyfish-dev)] Customizable Real-time Communication Engine/SFU library focused on WebRTC. | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtc_engine.svg)](https://hex.pm/api/packages/membrane_rtc_engine) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtc_engine/) |
| [kino_membrane](https://github.com/membraneframework/kino_membrane) | Utilities for introspecting Membrane pipelines in Livebook | [![Hex.pm](https://img.shields.io/hexpm/v/kino_membrane.svg)](https://hex.pm/api/packages/kino_membrane) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/kino_membrane/) |
| [docker_membrane](https://github.com/membraneframework-labs/docker_membrane) | [Labs] A docker image based on Ubuntu, with Erlang, Elixir and libraries necessary to test and run the Membrane Framework. |   |
| [membrane_demo](https://github.com/membraneframework/membrane_demo) | Examples of using the Membrane Framework |   |
| [membrane_tutorials](https://github.com/membraneframework/membrane_tutorials) | Repository which contains text and assets used in Membrane Framework tutorials. |   |

### Plugins

#### General purpose
| Package | Description | Links |
| --- | --- | --- |
| [membrane_file_plugin](https://github.com/membraneframework/membrane_file_plugin) | Membrane plugin for reading and writing to files | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_file_plugin.svg)](https://hex.pm/api/packages/membrane_file_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_file_plugin/) |
| [membrane_hackney_plugin](https://github.com/membraneframework/membrane_hackney_plugin) | HTTP sink and source based on Hackney | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_hackney_plugin.svg)](https://hex.pm/api/packages/membrane_hackney_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_hackney_plugin/) |
| [membrane_scissors_plugin](https://github.com/membraneframework/membrane_scissors_plugin) | Element for cutting off parts of the stream | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_scissors_plugin.svg)](https://hex.pm/api/packages/membrane_scissors_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_scissors_plugin/) |
| [membrane_tee_plugin](https://github.com/membraneframework/membrane_tee_plugin) | Membrane plugin for splitting data from a single input to multiple outputs | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_tee_plugin.svg)](https://hex.pm/api/packages/membrane_tee_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_tee_plugin/) |
| [membrane_funnel_plugin](https://github.com/membraneframework/membrane_funnel_plugin) | Membrane plugin for merging multiple input streams into a single output | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_funnel_plugin.svg)](https://hex.pm/api/packages/membrane_funnel_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_funnel_plugin/) |
| [membrane_realtimer_plugin](https://github.com/membraneframework/membrane_realtimer_plugin) | Membrane element limiting playback speed to realtime, according to buffers' timestamps | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_realtimer_plugin.svg)](https://hex.pm/api/packages/membrane_realtimer_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_realtimer_plugin/) |
| [membrane_stream_plugin](https://github.com/membraneframework/membrane_stream_plugin) | Plugin for recording the entire stream sent through Membrane pads into a binary format and replaying it | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_stream_plugin.svg)](https://hex.pm/api/packages/membrane_stream_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_stream_plugin/) |
| [membrane_fake_plugin](https://github.com/membraneframework/membrane_fake_plugin) | Fake Membrane sinks that drop incoming data | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_fake_plugin.svg)](https://hex.pm/api/packages/membrane_fake_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_fake_plugin/) |
| [membrane_pcap_plugin](https://github.com/membraneframework-labs/membrane_pcap_plugin) | [Labs] Membrane PCAP source, capable of reading captured packets in pcap format |   |
| [membrane_live_framerate_converter_plugin](https://github.com/kim-company/membrane_live_framerate_converter_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Membrane.Filter that drops or duplicates frames to match a target framerate. Designed for realtime applications |   |
| [membrane_template_plugin](https://github.com/membraneframework/membrane_template_plugin) | Template for Membrane Elements |   |

#### Streaming protocols
| Package | Description | Links |
| --- | --- | --- |
| [membrane_webrtc_plugin](https://github.com/jellyfish-dev/membrane_webrtc_plugin) | [Maintainer: [jellyfish-dev](https://github.com/jellyfish-dev)] Membrane plugin for sending and receiving media with WebRTC | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_webrtc_plugin.svg)](https://hex.pm/api/packages/membrane_webrtc_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_webrtc_plugin/) |
| [membrane_rtmp_plugin](https://github.com/membraneframework/membrane_rtmp_plugin) | RTMP server & client | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtmp_plugin.svg)](https://hex.pm/api/packages/membrane_rtmp_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtmp_plugin/) |
| [membrane_http_adaptive_stream_plugin](https://github.com/membraneframework/membrane_http_adaptive_stream_plugin) | Plugin generating manifests for HLS (DASH support planned) | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_http_adaptive_stream_plugin.svg)](https://hex.pm/api/packages/membrane_http_adaptive_stream_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_http_adaptive_stream_plugin/) |
| [membrane_ice_plugin](https://github.com/jellyfish-dev/membrane_ice_plugin) | [Maintainer: [jellyfish-dev](https://github.com/jellyfish-dev)] Membrane plugin for ICE protocol | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ice_plugin.svg)](https://hex.pm/api/packages/membrane_ice_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ice_plugin/) |
| [membrane_udp_plugin](https://github.com/membraneframework/membrane_udp_plugin) | Membrane plugin for sending and receiving UDP streams | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_udp_plugin.svg)](https://hex.pm/api/packages/membrane_udp_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_udp_plugin/) |
| [membrane_rtp_plugin](https://github.com/membraneframework/membrane_rtp_plugin) | Membrane bins and elements for sending and receiving RTP/SRTP and RTCP/SRTCP streams | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_plugin.svg)](https://hex.pm/api/packages/membrane_rtp_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_plugin/) |
| [membrane_rtp_h264_plugin](https://github.com/membraneframework/membrane_rtp_h264_plugin) | Membrane RTP payloader and depayloader for H264 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_h264_plugin.svg)](https://hex.pm/api/packages/membrane_rtp_h264_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_h264_plugin/) |
| [membrane_rtp_vp8_plugin](https://github.com/membraneframework/membrane_rtp_vp8_plugin) | Membrane elements for payloading and depayloading VP8 into RTP | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_vp8_plugin.svg)](https://hex.pm/api/packages/membrane_rtp_vp8_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_vp8_plugin/) |
| [membrane_rtp_vp9_plugin](https://github.com/membraneframework-labs/membrane_rtp_vp9_plugin) | [Labs] Membrane elements for payloading and depayloading VP9 into RTP |   |
| [membrane_rtp_mpegaudio_plugin](https://github.com/membraneframework/membrane_rtp_mpegaudio_plugin) | Membrane RTP MPEG Audio depayloader | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_mpegaudio_plugin.svg)](https://hex.pm/api/packages/membrane_rtp_mpegaudio_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_mpegaudio_plugin/) |
| [membrane_rtp_opus_plugin](https://github.com/membraneframework/membrane_rtp_opus_plugin) | Membrane RTP payloader and depayloader for OPUS audio | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_opus_plugin.svg)](https://hex.pm/api/packages/membrane_rtp_opus_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_opus_plugin/) |
| [membrane_quic_plugin](https://github.com/mickel8/membrane_quic_plugin) | [Maintainer: [mickel8](https://github.com/mickel8)]  |   |
| [membrane_mpeg_ts_plugin](https://github.com/kim-company/membrane_mpeg_ts_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Membrane.Filter that demuxes MPEG-TS streams |   |
| [membrane_hls_plugin](https://github.com/kim-company/membrane_hls_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Plugin providing a `Membrane.HLS.Source` element for HTTP Live Streaming (HLS). |   |

#### Containers
| Package | Description | Links |
| --- | --- | --- |
| [membrane_mp4_plugin](https://github.com/membraneframework/membrane_mp4_plugin) | Utilities for MP4 container parsing and serialization and elements for muxing the stream to CMAF | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mp4_plugin.svg)](https://hex.pm/api/packages/membrane_mp4_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mp4_plugin/) |
| [membrane_matroska_plugin](https://github.com/membraneframework/membrane_matroska_plugin) | Matroska muxer and demuxer | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_matroska_plugin.svg)](https://hex.pm/api/packages/membrane_matroska_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_matroska_plugin/) |
| [membrane_flv_plugin](https://github.com/membraneframework/membrane_flv_plugin) | Muxer and demuxer elements for FLV format | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_flv_plugin.svg)](https://hex.pm/api/packages/membrane_flv_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_flv_plugin/) |
| [membrane_ivf_plugin](https://github.com/membraneframework/membrane_ivf_plugin) | Plugin for converting video stream into IVF format | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ivf_plugin.svg)](https://hex.pm/api/packages/membrane_ivf_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ivf_plugin/) |
| [membrane_ogg_plugin](https://github.com/membraneframework/membrane_ogg_plugin) | Plugin for depayloading an Ogg file into an Opus stream | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ogg_plugin.svg)](https://hex.pm/api/packages/membrane_ogg_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ogg_plugin/) |

#### Audio codecs
| Package | Description | Links |
| --- | --- | --- |
| [membrane_aac_plugin](https://github.com/membraneframework/membrane_aac_plugin) | AAC parser and complementary elements for AAC codec | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_aac_plugin.svg)](https://hex.pm/api/packages/membrane_aac_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_aac_plugin/) |
| [membrane_aac_fdk_plugin](https://github.com/membraneframework/membrane_aac_fdk_plugin) | Membrane AAC decoder and encoder based on FDK library | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_aac_fdk_plugin.svg)](https://hex.pm/api/packages/membrane_aac_fdk_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_aac_fdk_plugin/) |
| [membrane_flac_plugin](https://github.com/membraneframework/membrane_flac_plugin) | Parser for files in FLAC bitstream format | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_flac_plugin.svg)](https://hex.pm/api/packages/membrane_flac_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_flac_plugin/) |
| [membrane_mp3_lame_plugin](https://github.com/membraneframework/membrane_mp3_lame_plugin) | Membrane MP3 encoder based on Lame | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mp3_lame_plugin.svg)](https://hex.pm/api/packages/membrane_mp3_lame_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mp3_lame_plugin/) |
| [membrane_mp3_mad_plugin](https://github.com/membraneframework/membrane_mp3_mad_plugin) | Membrane MP3 decoder based on MAD. | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mp3_mad_plugin.svg)](https://hex.pm/api/packages/membrane_mp3_mad_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mp3_mad_plugin/) |
| [membrane_opus_plugin](https://github.com/membraneframework/membrane_opus_plugin) | Membrane Opus encoder and decoder | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_opus_plugin.svg)](https://hex.pm/api/packages/membrane_opus_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_opus_plugin/) |
| [membrane_wav_plugin](https://github.com/membraneframework/membrane_wav_plugin) | Plugin providing elements handling audio in WAV file format. | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_wav_plugin.svg)](https://hex.pm/api/packages/membrane_wav_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_wav_plugin/) |

#### Video codecs
| Package | Description | Links |
| --- | --- | --- |
| [membrane_h264_plugin](https://github.com/membraneframework/membrane_h264_plugin) | Membrane h264 parser | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_h264_plugin.svg)](https://hex.pm/api/packages/membrane_h264_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_h264_plugin/) |
| [membrane_h264_ffmpeg_plugin](https://github.com/membraneframework/membrane_h264_ffmpeg_plugin) | Membrane H264 decoder and encoder based on FFmpeg and x264 | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_h264_ffmpeg_plugin.svg)](https://hex.pm/api/packages/membrane_h264_ffmpeg_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_h264_ffmpeg_plugin/) |
| [elixir-turbojpeg](https://github.com/BinaryNoggin/elixir-turbojpeg) | [Maintainer: [BinaryNoggin](https://github.com/BinaryNoggin)] libjpeg-turbo bindings for Elixir |   |
| [membrane_subtitle_mixer_plugin](https://github.com/kim-company/membrane_subtitle_mixer_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Membrane.Filter that uses CEA708 to merge subtitles directly in H264 packets. |   |

#### Raw audio & video
| Package | Description | Links |
| --- | --- | --- |
| [membrane_generator_plugin](https://github.com/membraneframework/membrane_generator_plugin) | Video and audio samples generator | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_generator_plugin.svg)](https://hex.pm/api/packages/membrane_generator_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_generator_plugin/) |

**Raw audio**
| Package | Description | Links |
| --- | --- | --- |
| [membrane_raw_audio_parser_plugin](https://github.com/membraneframework/membrane_raw_audio_parser_plugin) | Membrane element for parsing raw audio | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_raw_audio_parser_plugin.svg)](https://hex.pm/api/packages/membrane_raw_audio_parser_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_raw_audio_parser_plugin/) |
| [membrane_portaudio_plugin](https://github.com/membraneframework/membrane_portaudio_plugin) | Raw audio retriever and player based on PortAudio | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_portaudio_plugin.svg)](https://hex.pm/api/packages/membrane_portaudio_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_portaudio_plugin/) |
| [membrane_audio_mix_plugin](https://github.com/membraneframework/membrane_audio_mix_plugin) | Plugin providing an element mixing raw audio frames. | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_audio_mix_plugin.svg)](https://hex.pm/api/packages/membrane_audio_mix_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_audio_mix_plugin/) |
| [membrane_audio_filler_plugin](https://github.com/membraneframework/membrane_audio_filler_plugin) | Element for filling missing buffers in audio stream | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_audio_filler_plugin.svg)](https://hex.pm/api/packages/membrane_audio_filler_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_audio_filler_plugin/) |
| [membrane_ffmpeg_swresample_plugin](https://github.com/membraneframework/membrane_ffmpeg_swresample_plugin) | Plugin performing audio conversion, resampling and channel mixing, using SWResample module of FFmpeg library | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ffmpeg_swresample_plugin.svg)](https://hex.pm/api/packages/membrane_ffmpeg_swresample_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ffmpeg_swresample_plugin/) |
| [membrane_audiometer_plugin](https://github.com/membraneframework/membrane_audiometer_plugin) | Elements for measuring the level of the audio stream | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_audiometer_plugin.svg)](https://hex.pm/api/packages/membrane_audiometer_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_audiometer_plugin/) |

**Raw video**
| Package | Description | Links |
| --- | --- | --- |
| [membrane_raw_video_parser_plugin](https://github.com/membraneframework/membrane_raw_video_parser_plugin) | Membrane plugin for parsing raw video streams | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_raw_video_parser_plugin.svg)](https://hex.pm/api/packages/membrane_raw_video_parser_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_raw_video_parser_plugin/) |
| [membrane_video_merger_plugin](https://github.com/membraneframework/membrane_video_merger_plugin) | Membrane raw video cutter, merger and cut & merge bin | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_video_merger_plugin.svg)](https://hex.pm/api/packages/membrane_video_merger_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_video_merger_plugin/) |
| [membrane_video_compositor_plugin](https://github.com/membraneframework/membrane_video_compositor_plugin) | Membrane plugin that accepts multiple video inputs, transforms them according to provided transformations and composes them into a single output video. | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_video_compositor_plugin.svg)](https://hex.pm/api/packages/membrane_video_compositor_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_video_compositor_plugin/) |
| [membrane_camera_capture_plugin](https://github.com/membraneframework/membrane_camera_capture_plugin) | A set of elements allowing for capturing local media such as camera or microphone | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_camera_capture_plugin.svg)](https://hex.pm/api/packages/membrane_camera_capture_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_camera_capture_plugin/) |
| [membrane_framerate_converter_plugin](https://github.com/membraneframework/membrane_framerate_converter_plugin) | Element for converting frame rate of raw video stream | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_framerate_converter_plugin.svg)](https://hex.pm/api/packages/membrane_framerate_converter_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_framerate_converter_plugin/) |
| [membrane_sdl_plugin](https://github.com/membraneframework/membrane_sdl_plugin) | Membrane video player based on SDL | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_sdl_plugin.svg)](https://hex.pm/api/packages/membrane_sdl_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_sdl_plugin/) |
| [membrane_ffmpeg_swscale_plugin](https://github.com/membraneframework/membrane_ffmpeg_swscale_plugin) | Plugin providing an element scaling raw video frames, using SWScale module of FFmpeg library. | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ffmpeg_swscale_plugin.svg)](https://hex.pm/api/packages/membrane_ffmpeg_swscale_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ffmpeg_swscale_plugin/) |
| [membrane_ffmpeg_video_filter_plugin](https://github.com/membraneframework/membrane_ffmpeg_video_filter_plugin) | FFmpeg-based video filters | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ffmpeg_video_filter_plugin.svg)](https://hex.pm/api/packages/membrane_ffmpeg_video_filter_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ffmpeg_video_filter_plugin/) |
| [membrane_video_mixer_plugin](https://github.com/kim-company/membrane_video_mixer_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Membrane.Filter that mixes a variable number of input videos into one output using ffmpeg filters | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_video_mixer_plugin.svg)](https://hex.pm/api/packages/membrane_video_mixer_plugin)  |

#### External APIs
| Package | Description | Links |
| --- | --- | --- |
| [membrane_agora_plugin](https://github.com/membraneframework/membrane_agora_plugin) | Membrane Sink for Agora Server Gateway | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_agora_plugin.svg)](https://hex.pm/api/packages/membrane_agora_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_agora_plugin/) |
| [membrane_element_gcloud_speech_to_text](https://github.com/membraneframework/membrane_element_gcloud_speech_to_text) | Membrane plugin providing speech recognition via Google Cloud Speech-to-Text API | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_element_gcloud_speech_to_text.svg)](https://hex.pm/api/packages/membrane_element_gcloud_speech_to_text) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_element_gcloud_speech_to_text/) |
| [membrane_element_ibm_speech_to_text](https://github.com/membraneframework/membrane_element_ibm_speech_to_text) | Membrane plugin providing speech recognition via IBM Cloud Speech-to-Text service | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_element_ibm_speech_to_text.svg)](https://hex.pm/api/packages/membrane_element_ibm_speech_to_text) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_element_ibm_speech_to_text/) |
| [membrane_s3_plugin](https://github.com/YuzuTen/membrane_s3_plugin) | [Maintainer: [YuzuTen](https://github.com/YuzuTen)] Membrane framework plugin to support S3 sources/destinations | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_s3_plugin.svg)](https://hex.pm/api/packages/membrane_s3_plugin) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_s3_plugin/) |
| [membrane_transcription](https://github.com/lawik/membrane_transcription) | [Maintainer: [lawik](https://github.com/lawik)] Prototype transcription for Membrane |   |

### Formats
| Package | Description | Links |
| --- | --- | --- |
| [membrane_rtp_format](https://github.com/membraneframework/membrane_rtp_format) | Real-time Transport Protocol format for Membrane Framework | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtp_format.svg)](https://hex.pm/api/packages/membrane_rtp_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtp_format/) |
| [membrane_cmaf_format](https://github.com/membraneframework/membrane_cmaf_format) | Membrane description for Common Media Application Format | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_cmaf_format.svg)](https://hex.pm/api/packages/membrane_cmaf_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_cmaf_format/) |
| [membrane_matroska_format](https://github.com/membraneframework/membrane_matroska_format) | Matroska Membrane format | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_matroska_format.svg)](https://hex.pm/api/packages/membrane_matroska_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_matroska_format/) |
| [membrane_mp4_format](https://github.com/membraneframework/membrane_mp4_format) | MPEG-4 container Membrane format | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mp4_format.svg)](https://hex.pm/api/packages/membrane_mp4_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mp4_format/) |
| [membrane_raw_audio_format](https://github.com/membraneframework/membrane_raw_audio_format) | Raw audio format definition for the Membrane Multimedia Framework | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_raw_audio_format.svg)](https://hex.pm/api/packages/membrane_raw_audio_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_raw_audio_format/) |
| [membrane_raw_video_format](https://github.com/membraneframework/membrane_raw_video_format) | Membrane Multimedia Framework: Raw video format definition | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_raw_video_format.svg)](https://hex.pm/api/packages/membrane_raw_video_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_raw_video_format/) |
| [membrane_aac_format](https://github.com/membraneframework/membrane_aac_format) | Advanced Audio Codec Membrane format | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_aac_format.svg)](https://hex.pm/api/packages/membrane_aac_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_aac_format/) |
| [membrane_opus_format](https://github.com/membraneframework/membrane_opus_format) | Opus audio format definition for Membrane Framework | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_opus_format.svg)](https://hex.pm/api/packages/membrane_opus_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_opus_format/) |
| [membrane_flac_format](https://github.com/membraneframework/membrane_flac_format) | FLAC audio format description for Membrane Framework | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_flac_format.svg)](https://hex.pm/api/packages/membrane_flac_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_flac_format/) |
| [membrane_mpegaudio_format](https://github.com/membraneframework/membrane_mpegaudio_format) | MPEG audio format definition for Membrane Framework | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_mpegaudio_format.svg)](https://hex.pm/api/packages/membrane_mpegaudio_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_mpegaudio_format/) |
| [membrane_h264_format](https://github.com/membraneframework/membrane_h264_format) | Membrane Multimedia Framework: H264 video format definition | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_h264_format.svg)](https://hex.pm/api/packages/membrane_h264_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_h264_format/) |
| [membrane_vp8_format](https://github.com/membraneframework/membrane_vp8_format) | VP8 Membrane format | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_vp8_format.svg)](https://hex.pm/api/packages/membrane_vp8_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_vp8_format/) |
| [membrane_vp9_format](https://github.com/membraneframework/membrane_vp9_format) | VP9 Membrane format | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_vp9_format.svg)](https://hex.pm/api/packages/membrane_vp9_format) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_vp9_format/) |

### Standalone media libs
| Package | Description | Links |
| --- | --- | --- |
| [video_compositor](https://github.com/membraneframework/video_compositor) | Application for real-time video processing / transforming / composing |   |
| [ex_sdp](https://github.com/membraneframework/ex_sdp) | Parser and serializer for Session Description Protocol | [![Hex.pm](https://img.shields.io/hexpm/v/ex_sdp.svg)](https://hex.pm/api/packages/ex_sdp) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_sdp/) |
| [ex_libnice](https://github.com/membraneframework/ex_libnice) | Libnice-based Interactive Connectivity Establishment (ICE) protocol support for Elixir | [![Hex.pm](https://img.shields.io/hexpm/v/ex_libnice.svg)](https://hex.pm/api/packages/ex_libnice) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_libnice/) |
| [ex_libsrtp](https://github.com/membraneframework/ex_libsrtp) | Elixir bindings for libsrtp | [![Hex.pm](https://img.shields.io/hexpm/v/ex_libsrtp.svg)](https://hex.pm/api/packages/ex_libsrtp) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_libsrtp/) |
| [ex_dtls](https://github.com/membraneframework/ex_dtls) | DTLS and DTLS-SRTP handshake library for Elixir, based on OpenSSL | [![Hex.pm](https://img.shields.io/hexpm/v/ex_dtls.svg)](https://hex.pm/api/packages/ex_dtls) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_dtls/) |
| [membrane_rtsp](https://github.com/membraneframework/membrane_rtsp) | RTSP client for Elixir | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtsp.svg)](https://hex.pm/api/packages/membrane_rtsp) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtsp/) |
| [membrane_ffmpeg_generator](https://github.com/membraneframework-labs/membrane_ffmpeg_generator) | [Labs] FFmpeg video and audio generator for tests, benchmarks and demos. | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_ffmpeg_generator.svg)](https://hex.pm/api/packages/membrane_ffmpeg_generator) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_ffmpeg_generator/) |
| [webrtc-server](https://github.com/membraneframework/webrtc-server) | Signaling server for WebRTC |   |

### Utils
| Package | Description | Links |
| --- | --- | --- |
| [unifex](https://github.com/membraneframework/unifex) | Tool for generating interfaces between native C code and Elixir | [![Hex.pm](https://img.shields.io/hexpm/v/unifex.svg)](https://hex.pm/api/packages/unifex) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/unifex/) |
| [bundlex](https://github.com/membraneframework/bundlex) | Multiplatform app bundler tool for Elixir | [![Hex.pm](https://img.shields.io/hexpm/v/bundlex.svg)](https://hex.pm/api/packages/bundlex) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/bundlex/) |
| [beamchmark](https://github.com/membraneframework/beamchmark) | Elixir tool for benchmarking EVM performance | [![Hex.pm](https://img.shields.io/hexpm/v/beamchmark.svg)](https://hex.pm/api/packages/beamchmark) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/beamchmark/) |
| [bunch](https://github.com/membraneframework/bunch) | A bunch of helper functions, intended to make life easier | [![Hex.pm](https://img.shields.io/hexpm/v/bunch.svg)](https://hex.pm/api/packages/bunch) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/bunch/) |
| [bunch_native](https://github.com/membraneframework/bunch_native) | Native part of the Bunch package | [![Hex.pm](https://img.shields.io/hexpm/v/bunch_native.svg)](https://hex.pm/api/packages/bunch_native) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/bunch_native/) |
| [shmex](https://github.com/membraneframework/shmex) | Elixir bindings for shared memory | [![Hex.pm](https://img.shields.io/hexpm/v/shmex.svg)](https://hex.pm/api/packages/shmex) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/shmex/) |
| [membrane_common_c](https://github.com/membraneframework/membrane_common_c) | Membrane Multimedia Framework: Common C Routines | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_common_c.svg)](https://hex.pm/api/packages/membrane_common_c) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_common_c/) |
| [membrane_telemetry_metrics](https://github.com/membraneframework/membrane_telemetry_metrics) | Membrane tool for generating metrics | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_telemetry_metrics.svg)](https://hex.pm/api/packages/membrane_telemetry_metrics) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_telemetry_metrics/) |
| [membrane_opentelemetry](https://github.com/membraneframework-labs/membrane_opentelemetry) | [Labs] Utilities for using OpenTelemetry with Membrane | [![Hex.pm](https://img.shields.io/hexpm/v/membrane_opentelemetry.svg)](https://hex.pm/api/packages/membrane_opentelemetry) [![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_opentelemetry/) |

<!-- packages-list-end -->

## Copyright and License

Copyright 2018, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
