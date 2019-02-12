use Mix.Config

servers = [
  [host: "84.253.109.156", port: 7000]
]

config :acari_client,
  links: [
    #    [
    #      dev: "m1",
    #      servers: servers
    #    ],
    [
      dev: "m2",
      servers: servers
    ]
  ]
