# This script is used by .github/actions/close_issue/action.yml and it shouldn't be used in any other places.

Mix.install(json: "~> 1.4.1")

[issue_url] = System.argv()

:ok =
  IO.read(:stdio, :eof)
  |> JSON.decode!()
  |> Map.get("items")
  |> Enum.find(&(&1["content"]["url"] == issue_url))
  |> Map.get("id")
  |> then(&"\nTICKET_ID #{&1}\n")
  |> IO.puts()
