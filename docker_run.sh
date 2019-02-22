#!/bin/sh
docker run --rm -it \
--cap-add=NET_ADMIN \
--device /dev/net/tun:/dev/net/tun \
--volume ~/.config/acari_client:/opt/app/etc \
--name ac25 \
acari-client-25 $1
