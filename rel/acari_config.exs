# Вспомогательные переменный

server_port = 51019

servers = [
  [host: "84.253.109.155", port: server_port]
]

# Линки
m1_link = [
  dev: "m1",
  table: 101,
  servers: servers
]

m2_link = [
  dev: "m2",
  table: 102,
  servers: servers
]

eth_link = [
  dev: "eth1",
  table: 103,
  servers: [[host: "10.0.10.155", port: server_port]]
]

# Конфигурация клиента
# Дожна быть последним выражением в этом файле
[
  links: [m1_link, m2_link, eth_link]
]
