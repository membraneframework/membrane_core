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
    events: :all

  # config to test legacy version of telemetry
  # config :membrane_core, :telemetry_flags, [
  #   :report_init,
  #   :report_terminate,
  #   :report_buffer,
  #   :report_queue,
  #   :report_link,
  #   metrics: [
  #     :buffer,
  #     :bitrate,
  #     :queue_len,
  #     :stream_format,
  #     :event,
  #     :store,
  #     :take_and_demand
  #   ]
  # ]
end
