use Mix.Config

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n", level: :debug


config :acari_client, host: "10.0.10.10", port: 50019
