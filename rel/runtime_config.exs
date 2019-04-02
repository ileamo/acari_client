use Mix.Config

# Logger configuration
config :logger,
  backends: [:console, {LoggerFileBackend, :info_log}, {LoggerFileBackend, :error_log}]

config :logger, :info_log,
  path: "/var/log/info.log",
  format: "$date $time $metadata[$level] $message\n",
  level: :info

config :logger, :error_log,
  path: "/var/log/error.log",
  format: "$date $time $metadata[$level] $message\n",
  level: :error

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  level: :debug

config :acari_client, host: System.get_env("SRV_HOST"), port: 50019
