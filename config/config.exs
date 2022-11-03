import Config

if config_env() == :test do
  config :junit_formatter, include_filename?: true
end
