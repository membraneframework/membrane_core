defmodule Mix.Tasks.Membrane.Demo do
  @shortdoc "Download Membrane demos and examples"
  @moduledoc """
  Download Membrane demos and examples into the current directory. Requires `git` installed.

    $ mix membrane.demo [-a] [-l] [-d <repo_dir>] [<demos> ...]

  ## Options
  * `-l, --list` - List all demos available and their brief descriptions.
  * `-a, --all` - Pull the repository with all demos. 
  * `-d, --directory` - Specify a directory where the demos should be placed in.
  """
  use Mix.Task

  @switches [
    list: :boolean,
    all: :boolean,
    directory: :string
  ]

  @aliases [
    l: :list,
    a: :all,
    d: :directory
  ]

  @demos_search_list [".", "livebooks"]

  @demos_readme_url "https://raw.githubusercontent.com/membraneframework/membrane_demo/refs/heads/master/README.md"
  @demos_clone_url "https://github.com/membraneframework/membrane_demo.git"

  @impl true
  def run([]) do
    Mix.Tasks.Help.run(["membrane.demo"])
  end

  def run(argv) do
    {opts, demos_names} = OptionParser.parse!(argv, aliases: @aliases, switches: @switches)

    if opts[:list] do
      list_available_demos()
    end

    target_dir = Path.expand(opts[:directory] || ".")

    cond do
      opts[:all] -> copy_all_demos(target_dir)
      demos_names != [] -> copy_specific_demos(target_dir, demos_names)
      true -> :ok
    end
  end

  defp list_available_demos() do
    {:ok, _apps} = Application.ensure_all_started(:req)
    response = Req.get!(@demos_readme_url)

    demos_info =
      response.body
      |> String.split("\n")
      |> Enum.map(&Regex.named_captures(~r/^- \[(?<name>.*?)\]\(.*?\) - (?<description>.*)/, &1))
      |> Enum.filter(&(&1 != nil))
      |> Enum.map(
        &Map.update!(
          &1,
          "description",
          fn description -> Regex.replace(~r/\[(.*?)\]\(.*?\)/, description, "\\1") end
        )
      )

    max_name_length =
      demos_info
      |> Enum.map(&String.length(&1["name"]))
      |> Enum.max()

    demos_table =
      demos_info
      |> Enum.map_join("\n", fn %{"name" => name, "description" => description} ->
        dots_line = String.duplicate(".", max_name_length - String.length(name) + 3)
        " | #{name} #{dots_line} | #{description}"
      end)

    Mix.shell().info(demos_table)
  end

  defp copy_all_demos(target_dir) do
    repo_dir = Path.join(target_dir, "membrane_demo")
    execute_git_command(["clone", "-q", "--depth", "1", @demos_clone_url, repo_dir])
  end

  defp copy_specific_demos(target_dir, demos_names) do
    repo_dir = Path.join(target_dir, "membrane_demo")
    execute_git_command(["clone", "-q", "--depth", "1", "-n", @demos_clone_url, repo_dir])

    Enum.each(demos_names, fn demo_name ->
      case copy_demo(target_dir, demo_name) do
        :error ->
          Mix.shell().error(
            "No demo named #{demo_name}, run this task with -l to list all available demos"
          )

        :ok ->
          Mix.shell().info("`#{demo_name}` demo created at #{Path.join(target_dir, demo_name)}")
      end
    end)

    File.rm_rf!(repo_dir)
  end

  defp copy_demo(target_dir, demo_name) do
    repo_dir = Path.join(target_dir, "membrane_demo")

    Enum.reduce_while(@demos_search_list, :error, fn demo_dir, _status ->
      demo_path = Path.join([repo_dir, demo_dir, demo_name])

      execute_git_command(["sparse-checkout", "set", Path.join(demo_dir, demo_name)], repo_dir)
      execute_git_command(["checkout"], repo_dir)

      case File.cp_r(demo_path, Path.join(target_dir, Path.basename(demo_path))) do
        {:ok, _files} -> {:halt, :ok}
        {:error, :enoent, _dir} -> {:cont, :error}
      end
    end)
  end

  defp execute_git_command(argv, dir \\ ".") do
    case System.cmd("git", argv, stderr_to_stdout: true, cd: dir) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        Mix.shell().error("""
        Git command `git #{Enum.join(argv, " ")} exited with code #{exit_code}. Output:
        #{output}
        """)
    end
  end
end
