# This script is used by .github/actions/close_issue/action.yml and it shouldn't be used in any other places.

# It expects:
#   - output from `$ gh project item-list <project_id> --owner <owner> --format json --limit <limit>` command
#     on standard input
#   - URL of issue, that corresponds to one of the tickets included in the JSON data returned from the command
#     above. This URL should be passed as an argument in argv
# And prints `TICKET_ID <id>` on standard output, where `<id>` is id of a project item corresponding to the
# issue with the specified URL. Note, that beyond this, stdout can also contain some logs from `Mix.install/1`,
# e.g. `Resolving Hex dependencies...`.

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
