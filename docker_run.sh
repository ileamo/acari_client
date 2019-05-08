#!/bin/sh
docker run -it --rm \
  --name acari-client \
  -v /var/log/acari_client:/tmp/app/log \
  -v /etc/localtime:/etc/localtime:ro \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun \
  -d acari-client
