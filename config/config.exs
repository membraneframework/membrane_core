import Config

if Mix.env() == :test do
  config :junit_formatter, include_filename?: true
end
