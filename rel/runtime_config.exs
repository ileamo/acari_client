use Mix.Config

servers = [
  [host: "10.0.10.10", port: 7000]
]

config :acari_client,
  links: [
    [
      dev: "m1",
      servers: servers
    ],
    [
      dev: "m2",
      servers: servers
    ]
  ]
