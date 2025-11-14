Mix.install([{:req, "~> 0.4.0"}])

require Logger

{packages, _bindings} = Code.eval_file("packages.exs", __DIR__)

packages =
  packages
  |> Enum.map(fn
    {type, markdown} ->
      %{type: type, name: markdown}

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

# gh token for larger request rate
gh_auth_headers =
  case System.get_env("GITHUB_TOKEN") do
    nil -> []
    token -> [Authorization: "Bearer #{token}"]
  end

# fetch repos from the known organizations
repos =
  ["membraneframework", "membraneframework-labs", "fishjam-dev"]
  |> Enum.flat_map(fn org ->
    Stream.from_index()
    |> Stream.map(fn page ->
      if gh_auth_headers == [], do: Process.sleep(gh_req_timeout)
      url = "https://api.github.com/orgs/#{org}/repos?per_page=100&page=#{page}"
      Logger.debug("Fetching #{url}")

      resp =
        Req.get!(url, headers: gh_auth_headers, decode_json: [keys: :atoms]).body

      unless is_list(resp) do
        raise "Received invalid response: #{inspect(resp)}"
      end

      resp
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
  "github_actions_test",
  "membrane_ice_plugin"
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
            if gh_auth_headers == [], do: Process.sleep(gh_req_timeout)
            url = "https://api.github.com/repos/#{owner}/#{name}"
            Logger.debug("Fetching #{url}")

            Req.get!(url, headers: gh_auth_headers, decode_json: [keys: :atoms]).body

          Map.has_key?(repos, name) ->
            Map.fetch!(repos, name)

          true ->
            raise "Package #{inspect(name)} repo not found, please specify owner."
        end

      hex = Req.get!("https://hex.pm/api/packages/#{name}", decode_json: [keys: :atoms])

      hex_badge =
        if hex.status == 200 and hex.body.url != nil do
          "[![Hex.pm](https://img.shields.io/hexpm/v/#{name}.svg)](#{hex.body.url})"
        end

      hexdocs_badge =
        if hex.status == 200 and hex.body.docs_html_url != nil do
          "[![Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](#{hex.body.docs_html_url})"
        end

      github_badge =
        "[![GitHub](https://img.shields.io/badge/github-code-white.svg?logo=github)](#{repo.html_url})"

      owner_prefix =
        case repo.owner.login do
          "membraneframework-labs" -> "[Labs] "
          "membraneframework" -> ""
          owner -> "[Maintainer: [#{owner}](https://github.com/#{owner})] "
        end

      Map.merge(package, %{
        owner: repo.owner.login,
        url: repo.html_url,
        description: repo.description,
        owner_prefix: owner_prefix,
        hex_badge: hex_badge,
        hexdocs_badge: hexdocs_badge,
        github_badge: github_badge
      })

    other ->
      other
  end)

# generate packages list in markdown

header = """

| Package | Description | Links |
| --- | --- | --- |
"""

generated_code_comment =
  "<!-- Generated code, do not edit. See `scripts/elixir/update_packages_list.exs`. -->"

packages_md =
  packages
  |> Enum.map_reduce(
    %{is_header_present: false},
    fn
      %{type: :section, name: name}, acc ->
        {"\n### " <> name, %{acc | is_header_present: false}}

      %{type: :subsection, name: name}, acc ->
        {"\n#### " <> name, %{acc | is_header_present: false}}

      %{type: :package} = package, acc ->
        package_info = """
        #{if acc.is_header_present, do: "", else: header}\
        | [#{package.name}](#{package.url}) | #{package.owner_prefix}#{package.description} | #{package.hex_badge} #{package.hexdocs_badge} |\
        """

        {package_info, %{acc | is_header_present: true}}
    end
  )
  |> elem(0)
  |> Enum.join("\n")

packages_md =
  """
  <!-- packages-list-start -->
  #{generated_code_comment}

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

# update packages in docs
packages_docs_path = "guides/packages"

File.rm_rf!(packages_docs_path)
File.mkdir_p(packages_docs_path)

packages
|> Enum.reduce(
  %{file_path: nil, file_number: 0, section: nil, files: []},
  fn
    %{type: :package} = package, acc ->
      package_info = """
      ## #{package.name}
      #{package.owner_prefix}#{package.description} 

      #{package.hex_badge} #{package.hexdocs_badge} #{package.github_badge}
       
      """

      files =
        List.update_at(acc.files, 0, fn {file_path, file_content} ->
          {file_path, file_content <> package_info}
        end)

      %{acc | files: files}

    %{type: type, name: name}, acc ->
      # So that the files have correct order
      prefix = "#{acc.file_number}_" |> String.pad_leading(3, "0")

      {filename, section} =
        case type do
          :section -> {name, name}
          :subsection -> {"#{acc.section} | #{name}", acc.section}
        end

      file_path =
        Path.join(packages_docs_path, prefix <> filename <> ".md") |> String.replace(" ", "_")

      files = [{file_path, ""} | acc.files]

      %{
        acc
        | file_path: file_path,
          section: section,
          file_number: acc.file_number + 1,
          files: files
      }
  end
)
|> Map.get(:files)
|> Enum.each(fn {file_path, file_content} ->
  if file_content != "", do: File.write!(file_path, "#{generated_code_comment}\n#{file_content}")
end)

IO.puts("Packages updated successfully.")
