import Config

if config_env() == :test do
  config :junit_formatter, include_filename?: true

  config :membrane_core, :telemetry_flags, include: [
    :links,
    :inits_and_terminates,
    :spans
    # {:metrics, [:buffer, :bitrate, :queue_len, :stream_format, :event, :store, :take_and_demand]}
  ]
end
