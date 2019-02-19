use Mix.Config

servers = [
  [host: "84.253.109.156", port: 50019]
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
    ]
  ]
