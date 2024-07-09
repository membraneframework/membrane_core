Mix.install([{:req, "~> 0.4.0"}])

require Logger

# define packages structure
packages =
  [
    {:md, "### General"},
    "membrane_sdk",
    "membrane_core",
    "membrane_rtc_engine",
    "kino_membrane",
    "docker_membrane",
    "membrane_demo",
    "membrane_tutorials",
    {:md, "### Plugins"},
    {:md, "#### General purpose"},
    "membrane_file_plugin",
    "membrane_hackney_plugin",
    "membrane_scissors_plugin",
    "membrane_tee_plugin",
    "membrane_funnel_plugin",
    "membrane_realtimer_plugin",
    "membrane_stream_plugin",
    "membrane_fake_plugin",
    "membrane_pcap_plugin",
    "kim-company/membrane_live_framerate_converter_plugin",
    "membrane_template_plugin",
    {:md, "#### Streaming protocols"},
    "membrane_webrtc_plugin",
    "membrane_rtmp_plugin",
    "membrane_http_adaptive_stream_plugin",
    "membrane_ice_plugin",
    "membrane_udp_plugin",
    "membrane_tcp_plugin",
    "membrane_rtp_plugin",
    "membrane_rtp_h264_plugin",
    "membrane_rtp_vp8_plugin",
    "membrane_rtp_vp9_plugin",
    "membrane_rtp_mpegaudio_plugin",
    "membrane_rtp_opus_plugin",
    "membrane_rtp_g711_plugin",
    "mickel8/membrane_quic_plugin",
    "kim-company/membrane_mpeg_ts_plugin",
    "kim-company/membrane_hls_plugin",
    {:md, "#### Containers"},
    "membrane_mp4_plugin",
    "membrane_matroska_plugin",
    "membrane_flv_plugin",
    "membrane_ivf_plugin",
    "membrane_ogg_plugin",
    {:md, "#### Audio codecs"},
    "membrane_aac_plugin",
    "membrane_aac_fdk_plugin",
    "membrane_flac_plugin",
    "membrane_mp3_lame_plugin",
    "membrane_mp3_mad_plugin",
    "membrane_opus_plugin",
    "membrane_wav_plugin",
    "membrane_g711_plugin",
    {:md, "#### Video codecs"},
    "membrane_h26x_plugin",
    "membrane_h264_ffmpeg_plugin",
    "membrane_vpx_plugin",
    "membrane_abr_transcoder_plugin",
    "gBillal/membrane_h265_ffmpeg_plugin",
    "binarynoggin/elixir-turbojpeg",
    "kim-company/membrane_subtitle_mixer_plugin",
    {:md, "#### Raw audio & video"},
    "membrane_generator_plugin",
    {:md, "**Raw audio**"},
    "membrane_raw_audio_parser_plugin",
    "membrane_portaudio_plugin",
    "membrane_audio_mix_plugin",
    "membrane_audio_filler_plugin",
    "membrane_ffmpeg_swresample_plugin",
    "membrane_audiometer_plugin",
    {:md, "**Raw video**"},
    "membrane_raw_video_parser_plugin",
    "membrane_video_merger_plugin",
    "membrane_live_compositor_plugin",
    "membrane_camera_capture_plugin",
    "membrane_rpicam_plugin",
    "membrane_framerate_converter_plugin",
    "membrane_sdl_plugin",
    "membrane_overlay_plugin",
    "membrane_ffmpeg_swscale_plugin",
    "membrane_ffmpeg_video_filter_plugin",
    "kim-company/membrane_video_mixer_plugin",
    {:md, "#### External APIs"},
    "membrane_aws_plugin",
    "membrane_agora_plugin",
    "membrane_element_gcloud_speech_to_text",
    "membrane_element_ibm_speech_to_text",
    "YuzuTen/membrane_s3_plugin",
    "lawik/membrane_transcription",
    {:md, "### Formats"},
    "membrane_rtp_format",
    "membrane_cmaf_format",
    "membrane_matroska_format",
    "membrane_mp4_format",
    "membrane_raw_audio_format",
    "membrane_raw_video_format",
    "membrane_aac_format",
    "membrane_opus_format",
    "membrane_flac_format",
    "membrane_mpegaudio_format",
    "membrane_h264_format",
    "membrane_vp8_format",
    "membrane_vp9_format",
    "membrane_g711_format",
    {:md, "### Standalone media libs"},
    "elixir-webrtc/ex_webrtc",
    "live_compositor",
    "ex_sdp",
    "ex_libnice",
    "ex_libsrtp",
    "ex_m3u8",
    "membrane_rtsp",
    "membrane_ffmpeg_generator",
    {:md, "### Utils"},
    "unifex",
    "bundlex",
    "beamchmark",
    "bunch",
    "bunch_native",
    "shmex",
    "membrane_timestamp_queue",
    "membrane_common_c",
    "membrane_telemetry_metrics",
    "membrane_opentelemetry",
    "membrane_precompiled_dependency_provider"
  ]
  |> Enum.map(fn
    {:md, markdown} ->
      %{type: :markdown, content: markdown}

    package when is_binary(package) ->
      case String.split(package, "/", parts: 2) do
        [owner, name] -> %{type: :package, name: name, owner: owner}
        [name] -> %{type: :package, name: name, owner: nil}
      end
  end)

# to prevent exceeding API request rate
gh_req_timeout = 500

# for debugging, allows mocking requests for particular repos
gh_req_mock = false

# fetch repos from the known organizations
repos =
  ["membraneframework", "membraneframework-labs", "fishjam-dev"]
  |> Enum.flat_map(fn org ->
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn page ->
      Process.sleep(gh_req_timeout)
      url = "https://api.github.com/orgs/#{org}/repos?per_page=100&page=#{page}"
      Logger.debug("Fetching #{url}")
      Req.get!(url, decode_json: [keys: :atoms]).body
    end)
    |> Enum.take_while(&(&1 != []))
    |> Enum.flat_map(& &1)
  end)
  |> Enum.reverse()
  |> Map.new(&{&1.name, &1})

# find repos from the membraneframework organization that aren't in the list

package_names =
  packages |> Enum.filter(&(&1.type == :package)) |> MapSet.new(& &1.name)

packages_blacklist = [
  "circleci-orb",
  "design-system",
  ~r/.*_tutorial/,
  "membrane_resources",
  "static",
  ".github",
  "membraneframework.github.io",
  "membrane_rtc_engine_timescaledb",
  "membrane_g711_ffmpeg_plugin",
  "github_actions_test"
]

lacking_repos =
  repos
  |> Map.values()
  |> Enum.filter(fn repo ->
    repo.name not in package_names and
      repo.owner.login in ["membraneframework", "fishjam-dev"] and
      (repo.owner.login == "membraneframework" or repo.name =~ ~r/^membrane_.*/) and
      not Enum.any?(packages_blacklist, fn name -> repo.name =~ name end)
  end)

unless Enum.empty?(lacking_repos) do
  raise """
  The following repositories aren't mentioned in the package list:
  #{Enum.map_join(lacking_repos, ",\n", & &1.name)}
  """
end

# equip packages with the data from GH and Hex
packages =
  Enum.map(packages, fn
    %{type: :package, name: name, owner: owner} = package ->
      repo =
        cond do
          owner != nil and gh_req_mock ->
            %{owner: %{login: :mock}, html_url: :mock, description: :mock}

          owner != nil ->
            Process.sleep(gh_req_timeout)
            url = "https://api.github.com/repos/#{owner}/#{name}"
            Logger.debug("Fetching #{url}")
            Req.get!(url, decode_json: [keys: :atoms]).body

          Map.has_key?(repos, name) ->
            Map.fetch!(repos, name)

          true ->
            raise "Package #{inspect(name)} repo not found, please specify owner."
        end

      hex = Req.get!("https://hex.pm/api/packages/#{name}", decode_json: [keys: :atoms])
      is_hex_present = hex.status == 200

      Map.merge(package, %{
        owner: repo.owner.login,
        url: repo.html_url,
        description: repo.description,
        hex_url: if(is_hex_present, do: hex.body.url),
        hexdocs_url: if(is_hex_present, do: hex.body.docs_html_url)
      })

    other ->
      other
  end)

# generate packages list in markdown

header = """
| Package | Description | Links |
| --- | --- | --- |
"""

packages_md =
  packages
  |> Enum.map_reduce(%{is_header_present: false}, fn
    %{type: :markdown, content: content}, acc ->
      {"\n#{content}", %{acc | is_header_present: false}}

    %{type: :package} = package, acc ->
      prefix =
        case package.owner do
          "membraneframework-labs" -> "[Labs] "
          "membraneframework" -> ""
          _other -> "[Maintainer: [#{package.owner}](https://github.com/#{package.owner})] "
        end

      hex_badge =
        if package.hex_url,
          do:
            "[![Hex.pm](https://img.shields.io/hexpm/v/#{package.name}.svg)](#{package.hex_url})"

      hexdocs_badge =
        if package.hexdocs_url,
          do:
            "[![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](#{package.hexdocs_url})"

      url = "[#{package.name}](#{package.url})"

      result = """
      #{if acc.is_header_present, do: "", else: header}\
      | #{url} | #{prefix}#{package.description} | #{hex_badge} #{hexdocs_badge} |\
      """

      {result, %{acc | is_header_present: true}}
  end)
  |> elem(0)
  |> Enum.join("\n")

packages_md =
  """
  <!-- packages-list-start -->
  <!-- Generated code, do not edit. See `scripts/elixir/update_packages_list.exs`. -->

  #{packages_md}

  <!-- packages-list-end -->\
  """

# replace packages list in the readme

readme_path = "README.md"

File.read!(readme_path)
|> String.replace(
  ~r/<!-- packages-list-start -->(.|\n)*<!-- packages-list-end -->/m,
  packages_md
)
|> then(&File.write!(readme_path, &1))

IO.puts("Packages updated successfully.")
