defmodule Mix.Tasks.Membrane.DemoTest do
  use ExUnit.Case
  alias Mix.Tasks.Membrane.Demo

  setup do
    Mix.shell(Mix.Shell.Process)
  end

  describe "All listed demos are pulled" do
    @tag :tmp_dir
    test "individually", %{tmp_dir: tmp} do
      Demo.run(["-l"])

      get_available_demos_list()
      |> Enum.each(fn demo ->
        Demo.run(["-d", tmp, demo])

        receive do
          msg -> assert {:mix_shell, :info, _message} = msg
        end
      end)
    end

    @tag :tmp_dir
    test "all at once", %{tmp_dir: tmp} do
      demos_list = get_available_demos_list()
      Demo.run(["-d", tmp] ++ demos_list)

      Enum.each(demos_list, fn _demo ->
        receive do
          msg -> assert {:mix_shell, :info, _message} = msg
        end
      end)
    end
  end

  defp get_available_demos_list() do
    Demo.run(["-l"])

    receive do
      {:mix_shell, :info, [table]} ->
        table
        |> String.split("\n")
        |> Enum.map(&Regex.named_captures(~r/\| (?<name>\w+)/, &1)["name"])
    end
  end
end
