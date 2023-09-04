Mix.install([{:req, "~> 0.4.0"}, :kino])

require Logger

# define packages structure
packages =
  [
    {:md, "### General"},
    "membrane_core",
    "kino_membrane",
    "docker_membrane",
    "membrane_demo",
    "membrane_tutorials",
    {:md, "### Plugins"},
    {:md, "#### General purpose"},
    "membrane_file_plugin",
    "membrane_udp_plugin",
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
    "membrane_rtp_plugin",
    "membrane_rtp_h264_plugin",
    "membrane_rtp_vp8_plugin",
    "membrane_rtp_vp9_plugin",
    "membrane_rtp_mpegaudio_plugin",
    "membrane_rtp_opus_plugin",
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
    {:md, "#### Video codecs"},
    "membrane_h264_plugin",
    "membrane_h264_ffmpeg_plugin",
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
    "membrane_video_compositor_plugin",
    "membrane_camera_capture_plugin",
    "membrane_framerate_converter_plugin",
    "membrane_sdl_plugin",
    "membrane_ffmpeg_swscale_plugin",
    "membrane_ffmpeg_video_filter_plugin",
    "kim-company/membrane_video_mixer_plugin",
    {:md, "#### External APIs"},
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
    {:md, "### Standalone media libs"},
    "video_compositor",
    "ex_sdp",
    "ex_libnice",
    "ex_libsrtp",
    "ex_dtls",
    "membrane_rtsp",
    "membrane_ffmpeg_generator",
    "membrane_telemetry_dashboard",
    "webrtc-server",
    {:md, "### Utils"},
    "unifex",
    "bundlex",
    "beamchmark",
    "bunch",
    "bunch_native",
    "shmex",
    "membrane_common_c",
    "membrane_telemetry_metrics",
    "membrane_opentelemetry"
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
  ["membraneframework", "membraneframework-labs", "jellyfish-dev"]
  |> Enum.flat_map(fn org ->
    Process.sleep(gh_req_timeout)

    Req.get!(
      "https://api.github.com/orgs/#{org}/repos?per_page=100",
      decode_json: [keys: :atoms]
    ).body
  end)
  |> Map.new(&{&1.name, &1})


# find repos from the membraneframework organization that aren't in the list

package_names =
  packages |> Enum.filter(&(&1.type == :package)) |> Enum.map(& &1.name) |> MapSet.new()

lacking_repos =
  repos
  |> Map.values()
  |> Enum.filter(&(&1.owner.login == "membraneframework"))
  |> Enum.map(& &1.name)
  |> Enum.reject(&(&1 in package_names))
  |> Enum.reject(
    &Enum.any?(
      [
        "circleci-orb",
        "guide",
        "design-system",
        ~r/.*_tutorial/,
        "membrane_resources",
        "membrane_gigachad",
        "static",
        "membrane_videoroom",
        ".github",
        "membraneframework.github.io"
      ],
      fn repo -> &1 =~ repo end
    )
  )

unless Enum.empty?(lacking_repos) do
  Logger.warning("""
  The following repositories from the membraneframework organization aren't mentioned in the package list:
  #{Enum.join(lacking_repos, ",\n")}
  """)
end

# equip packages with the data from GH and Hex
packages =
  Enum.map(packages, fn
    %{type: :package, name: name, owner: owner} = package ->
      repo =
        case Map.fetch(repos, name) do
          {:ok, repo} ->
            repo

          :error when owner != nil and gh_req_mock ->
            %{owner: %{login: :mock}, html_url: :mock, description: :mock}

          :error when owner != nil ->
            Process.sleep(gh_req_timeout)
            IO.puts("Fetching https://api.github.com/repos/#{owner}/#{name}")

            Req.get!("https://api.github.com/repos/#{owner}/#{name}", decode_json: [keys: :atoms]).body

          :error ->
            raise "Package #{inspect(name)} repo not found, please specify owner."
        end

      hex = Req.get!("https://hex.pm/api/packages/#{name}", decode_json: [keys: :atoms])
      hex_present = hex.status == 200

      Map.merge(package, %{
        owner: repo.owner.login,
        url: repo.html_url,
        description: repo.description,
        hex_url: if(hex_present, do: hex.body.url),
        hexdocs_url: if(hex_present, do: hex.body.docs_html_url)
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
  |> Enum.map_reduce(%{header_present: false}, fn
    %{type: :markdown, content: content}, acc ->
      {content, %{acc | header_present: false}}

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
      #{if acc.header_present, do: "", else: header}\
      | #{url} | #{prefix}#{package.description} | #{hex_badge}#{hexdocs_badge} |\
      """

      {result, %{acc | header_present: true}}
  end)
  |> elem(0)
  |> Enum.join("\n")

packages_md =
  """
  <!-- packages-list-start -->
  <!-- Generated code, do not edit. See `update_packages_list.exs`. -->

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
|> then(&File.write(readme_path, &1))
