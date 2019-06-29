# Вспомогательные переменные

server_port = 51019

servers = [
  [host: "demo.nsg.net.ru", port: 51019],
  [host: "demo.nsg.net.ru", port: 52019],
  [host: "demo.nsg.net.ru", port: 53019]
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

android_link = [
  dev: "lte",
  table: 100,
  servers: servers
]


# Конфигурация клиента
# Дожна быть последним выражением в этом файле
[
  iface: [addr: "172.31.255.1", peer: "172.30.254.1"],
  links: [android_link]
]
