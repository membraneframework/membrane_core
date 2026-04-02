
### General
| Package | Description |
| --- | --- |
| [membrane_sdk](https://github.com/membraneframework/membrane_sdk) | Full power of Membrane in a single package |
| [membrane_core](https://github.com/membraneframework/membrane_core) | The core of Membrane Framework, multimedia processing framework written in Elixir |
| [membrane_rtc_engine](https://github.com/fishjam-dev/membrane_rtc_engine) | [Maintainer: [fishjam-dev](https://github.com/fishjam-dev)] Customizable Real-time Communication Engine/SFU library focused on WebRTC. |
| [kino_membrane](https://github.com/membraneframework/kino_membrane) | Utilities for introspecting Membrane pipelines in Livebook |
| [docker_membrane](https://github.com/membraneframework-labs/docker_membrane) | [Labs] A docker image based on Ubuntu, with Erlang, Elixir and libraries necessary to test and run the Membrane Framework. |
| [membrane_demo](https://github.com/membraneframework/membrane_demo) | Examples of using the Membrane Framework |
| [membrane_tutorials](https://github.com/membraneframework/membrane_tutorials) | Repository which contains text and assets used in Membrane Framework tutorials. |
| [boombox](https://github.com/membraneframework/boombox) | Boombox is a simple streaming tool built on top of Membrane |

### Plugins

#### General purpose
| Package | Description |
| --- | --- |
| [membrane_file_plugin](https://github.com/membraneframework/membrane_file_plugin) | Membrane plugin for reading and writing to files |
| [membrane_hackney_plugin](https://github.com/membraneframework/membrane_hackney_plugin) | HTTP sink and source based on Hackney |
| [membrane_scissors_plugin](https://github.com/membraneframework/membrane_scissors_plugin) | Element for cutting off parts of the stream |
| [membrane_tee_plugin](https://github.com/membraneframework/membrane_tee_plugin) | Membrane plugin for splitting data from a single input to multiple outputs |
| [membrane_funnel_plugin](https://github.com/membraneframework/membrane_funnel_plugin) | Membrane plugin for merging multiple input streams into a single output |
| [membrane_realtimer_plugin](https://github.com/membraneframework/membrane_realtimer_plugin) | Membrane element limiting playback speed to realtime, according to buffers' timestamps |
| [membrane_stream_plugin](https://github.com/membraneframework/membrane_stream_plugin) | Plugin for recording the entire stream sent through Membrane pads into a binary format and replaying it |
| [membrane_fake_plugin](https://github.com/membraneframework/membrane_fake_plugin) | Fake Membrane sinks that drop incoming data |
| [membrane_pcap_plugin](https://github.com/membraneframework-labs/membrane_pcap_plugin) | [Labs] Membrane PCAP source, capable of reading captured packets in pcap format |
| [membrane_transcoder_plugin](https://github.com/membraneframework/membrane_transcoder_plugin) | Membrane plugin providing audio and video transcoding capabilities |
| [membrane_generator_plugin](https://github.com/membraneframework/membrane_generator_plugin) | Video and audio samples generator |
| [membrane_live_framerate_converter_plugin](https://github.com/kim-company/membrane_live_framerate_converter_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Membrane.Filter that drops or duplicates frames to match a target framerate. Designed for realtime applications |
| [membrane_template_plugin](https://github.com/membraneframework/membrane_template_plugin) | Template for Membrane Elements |

#### AI
| Package | Description |
| --- | --- |
| [membrane_whisper_plugin](https://github.com/membraneframework/membrane_whisper_plugin) | Membrane plugin for integrating OpenAI's Whisper in audio processing pipelines |
| [membrane_yolo_plugin](https://github.com/membraneframework/membrane_yolo_plugin) | Membrane Plugin for applying YOLO object detection on raw video frames |

#### Streaming protocols
| Package | Description |
| --- | --- |
| [membrane_webrtc_plugin](https://github.com/membraneframework/membrane_webrtc_plugin) | Plugin for streaming via WebRTC |
| [membrane_rtmp_plugin](https://github.com/membraneframework/membrane_rtmp_plugin) | RTMP server & client |
| [membrane_http_adaptive_stream_plugin](https://github.com/membraneframework/membrane_http_adaptive_stream_plugin) | Plugin generating manifests for HLS |
| [membrane_srt_plugin](https://github.com/membraneframework/membrane_srt_plugin) |  |
| [membrane_udp_plugin](https://github.com/membraneframework/membrane_udp_plugin) | Membrane plugin for sending and receiving UDP streams |
| [membrane_tcp_plugin](https://github.com/membraneframework/membrane_tcp_plugin) | Membrane plugin for sending and receiving TCP streams |
| [membrane_rtp_plugin](https://github.com/membraneframework/membrane_rtp_plugin) | Membrane bins and elements for sending and receiving RTP/SRTP and RTCP/SRTCP streams |
| [membrane_rtp_h264_plugin](https://github.com/membraneframework/membrane_rtp_h264_plugin) | Membrane RTP payloader and depayloader for H264 |
| [membrane_rtp_aac_plugin](https://github.com/membraneframework/membrane_rtp_aac_plugin) | RTP AAC depayloader |
| [membrane_rtp_vp8_plugin](https://github.com/membraneframework/membrane_rtp_vp8_plugin) | Membrane elements for payloading and depayloading VP8 into RTP |
| [membrane_rtp_vp9_plugin](https://github.com/membraneframework-labs/membrane_rtp_vp9_plugin) | [Labs] Membrane elements for payloading and depayloading VP9 into RTP |
| [membrane_rtp_mpegaudio_plugin](https://github.com/membraneframework/membrane_rtp_mpegaudio_plugin) | Membrane RTP MPEG Audio depayloader |
| [membrane_rtp_opus_plugin](https://github.com/membraneframework/membrane_rtp_opus_plugin) | Membrane RTP payloader and depayloader for OPUS audio |
| [membrane_rtp_g711_plugin](https://github.com/membraneframework/membrane_rtp_g711_plugin) | Membrane RTP payloader and depayloader for G711 audio |
| [membrane_rtsp_plugin](https://github.com/gBillal/membrane_rtsp_plugin) | [Maintainer: [gBillal](https://github.com/gBillal)] Simplify connecting to RTSP server |
| [membrane_mpeg_ts_plugin](https://github.com/kim-company/membrane_mpeg_ts_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Membrane.Filter that demuxes MPEG-TS streams |
| [membrane_hls_plugin](https://github.com/kim-company/membrane_hls_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Adaptive live streaming plugin (HLS) for the Membrane Framework |

#### Containers
| Package | Description |
| --- | --- |
| [membrane_mp4_plugin](https://github.com/membraneframework/membrane_mp4_plugin) | Utilities for MP4 container parsing and serialization and elements for muxing the stream to CMAF |
| [membrane_matroska_plugin](https://github.com/membraneframework/membrane_matroska_plugin) | Matroska muxer and demuxer |
| [membrane_flv_plugin](https://github.com/membraneframework/membrane_flv_plugin) | Muxer and demuxer elements for FLV format |
| [membrane_ivf_plugin](https://github.com/membraneframework/membrane_ivf_plugin) | Plugin for converting video stream into IVF format |
| [membrane_ogg_plugin](https://github.com/membraneframework/membrane_ogg_plugin) | Plugin for depayloading an Ogg file into an Opus stream |

#### Audio codecs
| Package | Description |
| --- | --- |
| [membrane_aac_plugin](https://github.com/membraneframework/membrane_aac_plugin) | AAC parser and complementary elements for AAC codec |
| [membrane_aac_fdk_plugin](https://github.com/membraneframework/membrane_aac_fdk_plugin) | Membrane AAC decoder and encoder based on FDK library |
| [membrane_flac_plugin](https://github.com/membraneframework/membrane_flac_plugin) | Parser for files in FLAC bitstream format |
| [membrane_mp3_lame_plugin](https://github.com/membraneframework/membrane_mp3_lame_plugin) | Membrane MP3 encoder based on Lame |
| [membrane_mp3_mad_plugin](https://github.com/membraneframework/membrane_mp3_mad_plugin) | Membrane MP3 decoder based on MAD. |
| [membrane_opus_plugin](https://github.com/membraneframework/membrane_opus_plugin) | Membrane Opus encoder and decoder |
| [membrane_wav_plugin](https://github.com/membraneframework/membrane_wav_plugin) | Plugin providing elements handling audio in WAV file format. |
| [membrane_g711_plugin](https://github.com/membraneframework/membrane_g711_plugin) | Membrane G.711 decoder, encoder and parser |
| [membrane_g711_ffmpeg_plugin](https://github.com/membraneframework/membrane_g711_ffmpeg_plugin) | Membrane G.711 decoder and encoder based on FFmpeg |

#### Video codecs
| Package | Description |
| --- | --- |
| [membrane_h26x_plugin](https://github.com/membraneframework/membrane_h26x_plugin) | Membrane h264 and h265 parsers |
| [membrane_h264_ffmpeg_plugin](https://github.com/membraneframework/membrane_h264_ffmpeg_plugin) | Membrane H264 decoder and encoder based on FFmpeg and x264 |
| [membrane_vpx_plugin](https://github.com/membraneframework/membrane_vpx_plugin) | Membrane plugin for decoding and encoding VP8 and VP9 streams |
| [membrane_abr_transcoder_plugin](https://github.com/membraneframework/membrane_abr_transcoder_plugin) | ABR (adaptive bitrate) transcoder, that accepts an h.264 video and outputs multiple variants of it with different qualities. |
| [membrane_vk_video_plugin](https://github.com/membraneframework/membrane_vk_video_plugin) | Membrane H.264 decoder and encoder based on vk-video |
| [membrane_h265_ffmpeg_plugin](https://github.com/gBillal/membrane_h265_ffmpeg_plugin) | [Maintainer: [gBillal](https://github.com/gBillal)] Membrane H265 decoder and encoder based on FFmpeg and x265 |
| [elixir-turbojpeg](https://github.com/BinaryNoggin/elixir-turbojpeg) | [Maintainer: [BinaryNoggin](https://github.com/BinaryNoggin)] libjpeg-turbo bindings for Elixir |
| [membrane_subtitle_mixer_plugin](https://github.com/kim-company/membrane_subtitle_mixer_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Membrane.Filter that uses CEA708 to merge subtitles directly in H264 packets. |

#### Raw audio
| Package | Description |
| --- | --- |
| [membrane_raw_audio_parser_plugin](https://github.com/membraneframework/membrane_raw_audio_parser_plugin) | Membrane element for parsing raw audio |
| [membrane_portaudio_plugin](https://github.com/membraneframework/membrane_portaudio_plugin) | Raw audio retriever and player based on PortAudio |
| [membrane_audio_mix_plugin](https://github.com/membraneframework/membrane_audio_mix_plugin) | Plugin providing an element mixing raw audio frames. |
| [membrane_audio_filler_plugin](https://github.com/membraneframework/membrane_audio_filler_plugin) | Element for filling missing buffers in audio stream |
| [membrane_ffmpeg_swresample_plugin](https://github.com/membraneframework/membrane_ffmpeg_swresample_plugin) | Plugin performing audio conversion, resampling and channel mixing, using SWResample module of FFmpeg library |
| [membrane_audiometer_plugin](https://github.com/membraneframework/membrane_audiometer_plugin) | Elements for measuring the level of the audio stream |

#### Raw video
| Package | Description |
| --- | --- |
| [membrane_raw_video_parser_plugin](https://github.com/membraneframework/membrane_raw_video_parser_plugin) | Membrane plugin for parsing raw video streams |
| [membrane_video_merger_plugin](https://github.com/membraneframework/membrane_video_merger_plugin) | Membrane raw video cutter, merger and cut & merge bin |
| [membrane_smelter_plugin](https://github.com/membraneframework/membrane_smelter_plugin) | Membrane plugin for video and audio mixing/compositing |
| [membrane_camera_capture_plugin](https://github.com/membraneframework/membrane_camera_capture_plugin) | A set of elements allowing for capturing local media such as camera or microphone |
| [membrane_rpicam_plugin](https://github.com/membraneframework/membrane_rpicam_plugin) | Membrane rpicam plugin |
| [membrane_framerate_converter_plugin](https://github.com/membraneframework/membrane_framerate_converter_plugin) | Element for converting frame rate of raw video stream |
| [membrane_sdl_plugin](https://github.com/membraneframework/membrane_sdl_plugin) | Membrane video player based on SDL |
| [membrane_overlay_plugin](https://github.com/membraneframework/membrane_overlay_plugin) | Filter for applying overlay image or text on top of video |
| [membrane_ffmpeg_swscale_plugin](https://github.com/membraneframework/membrane_ffmpeg_swscale_plugin) | Plugin providing an element scaling raw video frames, using SWScale module of FFmpeg library. |
| [membrane_ffmpeg_video_filter_plugin](https://github.com/membraneframework/membrane_ffmpeg_video_filter_plugin) | FFmpeg-based video filters |
| [membrane_video_mixer_plugin](https://github.com/kim-company/membrane_video_mixer_plugin) | [Maintainer: [kim-company](https://github.com/kim-company)] Membrane.Filter that mixes a variable number of input videos into one output using ffmpeg filters |

#### External APIs
| Package | Description |
| --- | --- |
| [membrane_aws_plugin](https://github.com/fishjam-dev/membrane_aws_plugin) | [Maintainer: [fishjam-dev](https://github.com/fishjam-dev)]  |
| [membrane_agora_plugin](https://github.com/membraneframework/membrane_agora_plugin) | Membrane Sink for Agora Server Gateway |
| [membrane_element_gcloud_speech_to_text](https://github.com/membraneframework/membrane_element_gcloud_speech_to_text) | Membrane plugin providing speech recognition via Google Cloud Speech-to-Text API |
| [membrane_element_ibm_speech_to_text](https://github.com/membraneframework/membrane_element_ibm_speech_to_text) | Membrane plugin providing speech recognition via IBM Cloud Speech-to-Text service |
| [membrane_s3_plugin](https://github.com/YuzuTen/membrane_s3_plugin) | [Maintainer: [YuzuTen](https://github.com/YuzuTen)] Membrane framework plugin to support S3 sources/destinations |
| [membrane_transcription](https://github.com/lawik/membrane_transcription) | [Maintainer: [lawik](https://github.com/lawik)] Prototype transcription for Membrane |

### Formats
| Package | Description |
| --- | --- |
| [membrane_rtp_format](https://github.com/membraneframework/membrane_rtp_format) | Real-time Transport Protocol format for Membrane Framework |
| [membrane_cmaf_format](https://github.com/membraneframework/membrane_cmaf_format) | Membrane description for Common Media Application Format |
| [membrane_matroska_format](https://github.com/membraneframework/membrane_matroska_format) | Matroska Membrane format |
| [membrane_mp4_format](https://github.com/membraneframework/membrane_mp4_format) | MPEG-4 container Membrane format |
| [membrane_raw_audio_format](https://github.com/membraneframework/membrane_raw_audio_format) | Raw audio format definition for the Membrane Multimedia Framework |
| [membrane_raw_video_format](https://github.com/membraneframework/membrane_raw_video_format) | Membrane Multimedia Framework: Raw video format definition |
| [membrane_aac_format](https://github.com/membraneframework/membrane_aac_format) | Advanced Audio Codec Membrane format |
| [membrane_opus_format](https://github.com/membraneframework/membrane_opus_format) | Opus audio format definition for Membrane Framework |
| [membrane_flac_format](https://github.com/membraneframework/membrane_flac_format) | FLAC audio format description for Membrane Framework |
| [membrane_mpegaudio_format](https://github.com/membraneframework/membrane_mpegaudio_format) | MPEG audio format definition for Membrane Framework |
| [membrane_h264_format](https://github.com/membraneframework/membrane_h264_format) | Membrane Multimedia Framework: H264 video format definition |
| [membrane_vp8_format](https://github.com/membraneframework/membrane_vp8_format) | VP8 Membrane format |
| [membrane_vp9_format](https://github.com/membraneframework/membrane_vp9_format) | VP9 Membrane format |
| [membrane_g711_format](https://github.com/membraneframework/membrane_g711_format) | Membrane Multimedia Framework: G711 audio format definition |
| [membrane_av1_format](https://github.com/membraneframework/membrane_av1_format) | About Membrane Multimedia Framework: AV1 video format definition |
| [membrane_h265_format](https://github.com/gBillal/membrane_h265_format) | [Maintainer: [gBillal](https://github.com/gBillal)] H265 video format definition |

### Standalone media libs
| Package | Description |
| --- | --- |
| [ex_webrtc](https://github.com/elixir-webrtc/ex_webrtc) | [Maintainer: [elixir-webrtc](https://github.com/elixir-webrtc)] An Elixir implementation of the W3C WebRTC API |
| [ex_sdp](https://github.com/membraneframework/ex_sdp) | Parser and serializer for Session Description Protocol |
| [ex_libnice](https://github.com/membraneframework/ex_libnice) | Libnice-based Interactive Connectivity Establishment (ICE) protocol support for Elixir |
| [ex_libsrtp](https://github.com/membraneframework/ex_libsrtp) | Elixir bindings for libsrtp |
| [ex_m3u8](https://github.com/membraneframework/ex_m3u8) | Elixir package for serializing and deserializing M3U8 manifests. |
| [ex_hls](https://github.com/membraneframework/ex_hls) | An Elixir package for handling HLS streams |
| [ex_libsrt](https://github.com/membraneframework/ex_libsrt) | Elixir bindings to libsrt library exposing client and server APIs |
| [membrane_rtsp](https://github.com/membraneframework/membrane_rtsp) | RTSP client for Elixir |
| [membrane_ffmpeg_generator](https://github.com/membraneframework-labs/membrane_ffmpeg_generator) | [Labs] FFmpeg video and audio generator for tests, benchmarks and demos. |

### Utils
| Package | Description |
| --- | --- |
| [unifex](https://github.com/membraneframework/unifex) | Tool for generating interfaces between native C code and Elixir |
| [bundlex](https://github.com/membraneframework/bundlex) | Multiplatform app bundler tool for Elixir |
| [beamchmark](https://github.com/membraneframework/beamchmark) | Elixir tool for benchmarking EVM performance |
| [bunch](https://github.com/membraneframework/bunch) | A bunch of helper functions, intended to make life easier |
| [bunch_native](https://github.com/membraneframework/bunch_native) | Native part of the Bunch package |
| [shmex](https://github.com/membraneframework/shmex) | Elixir bindings for shared memory |
| [membrane_timestamp_queue](https://github.com/membraneframework/membrane_timestamp_queue) | Queue that aligns streams from multiple sources basing on timestamps |
| [membrane_common_c](https://github.com/membraneframework/membrane_common_c) | Membrane Multimedia Framework: Common C Routines |
| [membrane_telemetry_metrics](https://github.com/membraneframework/membrane_telemetry_metrics) | Membrane tool for generating metrics |
| [membrane_opentelemetry](https://github.com/membraneframework-labs/membrane_opentelemetry) | [Labs] Utilities for using OpenTelemetry with Membrane |
| [membrane_precompiled_dependency_provider](https://github.com/membraneframework/membrane_precompiled_dependency_provider) | Provides URLs for precompiled dependencies used by Membrane plugins. |