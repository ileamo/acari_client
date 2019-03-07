use Mix.Config

# Logger configuration
config :logger,
  backends: [:console, {LoggerFileBackend, :error_log}]

config :logger, :error_log,
  path: "log/info.log",
  format: "$date $time $metadata[$level] $message\n",
  level: :info

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  level: :debug

# Acari client configuration
servers = [
  [host: "84.253.109.155", port: 51019]
]

config :acari_client,
  links: [
    [
      dev: "m1",
      table: 101,
      servers: servers
    ],
    [
      dev: "m2",
      table: 102,
      servers: servers
    ],
    [
      dev: "eth1",
      table: 103,
      servers: [[host: "10.0.10.155", port: 51019]]
    ]
  ]
