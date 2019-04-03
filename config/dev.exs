use Mix.Config

config :acari_client, host: "localhost", port: 50019

config :logger,
  backends: [:console, {Loggix, :info_log}, {Loggix, :error_log}]

config :logger, :info_log,
  path: "_log/acari-client-info.log",
  format: "$date $time $metadata[$level] $message\n",
  rotate: %{max_bytes: 4096, keep: 5},
  level: :info

config :logger, :error_log,
  path: "_log/acari-client-error.log",
  format: "$date $time $metadata[$level] $message\n",
  rotate: %{max_bytes: 4096, keep: 5},
  level: :error

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  level: :debug
