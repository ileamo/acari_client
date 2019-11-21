import Config

config :acari_client, AcariClient.Endpoint,
  ip: {127, 0, 0, 1},
  port: 50021

import_config "#{Mix.env()}.exs"
