import Config

if config_env() == :test do
  config :junit_formatter, include_filename?: true

  config :membrane_core, :telemetry_flags,
    include: [
      :init,
      :setup,
      :terminate_request,
      :playing,
      :link
    ]
end
