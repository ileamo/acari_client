use Mix.Config

# Logger configuration
config :logger,
  backends: [{Loggix, :info_log}, {Loggix, :error_log}]

config :logger, :info_log,
  path: "/var/log/info.log",
  format: "$date $time $metadata[$level] $message\n",
  rotate: %{max_bytes: 2*1024*1024, keep: 5},
  level: :info

config :logger, :error_log,
  path: "/var/log/error.log",
  format: "$date $time $metadata[$level] $message\n",
  rotate: %{max_bytes: 2*1024*1024, keep: 5},
  level: :error

config :acari_client, host: System.get_env("SRV_HOST"), port: 50019
