import Config

if config_env() == :test do
  config :junit_formatter, include_filename?: true

  config :membrane_core, :telemetry_flags,
    tracked_callbacks: [
      element: [
        :handle_init,
        :handle_playing,
        :handle_setup,
        :handle_terminate_request,
        :handle_parent_notification
      ],
      bin: :all,
      pipeline: :all
    ],
    metrics: :all
end
