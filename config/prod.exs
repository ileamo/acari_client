import Config

# Logger configuration
config :logger,
  backends: [:console]

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  level: :info,
  colors: [enabled: false]
