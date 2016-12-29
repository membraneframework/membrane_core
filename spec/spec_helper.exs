Path.wildcard("spec/support/**/*.exs")
|> Enum.each(&Code.require_file/1)

ESpec.start
