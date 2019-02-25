FROM bitwalker/alpine-elixir-phoenix:1.8.0 AS build
RUN apk --no-cache update && apk --no-cache upgrade && apk --no-cache add openssl

WORKDIR /build

COPY mix.exs .
COPY mix.lock .
#COPY deps deps

ARG MIX_ENV=docker
ARG APP_VERSION=0.0.0
ENV MIX_ENV ${MIX_ENV}
ENV APP_VERSION ${APP_VERSION}

RUN mix deps.get

COPY lib lib
#COPY test test
COPY config config
COPY rel rel

# Uncomment line below if you have assets in the priv dir
# COPY priv priv

# Build Phoenix assets
#COPY assets assets
#RUN cd assets && npm install && ./node_modules/.bin/brunch build --production
#RUN mix phx.digest


RUN mix release --env=${MIX_ENV}

### Minimal run-time image
FROM alpine:3.8

RUN apk --no-cache update && apk --no-cache upgrade && apk --no-cache add openssl ncurses-libs bash ca-certificates zabbix-utils libcap iproute2 openssh

RUN ssh-keygen -A && \
  { \
    echo "PermitRootLogin yes"; \
    echo "PasswordAuthentication yes"; \
  } >> /etc/ssh/sshd_config

RUN adduser -D app

ARG MIX_ENV=docker
ARG APP_VERSION=0.0.0

ENV MIX_ENV ${MIX_ENV}
ENV APP_VERSION ${APP_VERSION}

WORKDIR /opt/app

# Copy release from build stage
COPY --from=build /build/_build/${MIX_ENV}/rel/* ./

RUN setcap cap_net_admin=ep /opt/app/erts-10.1.1/bin/beam.smp cap_net_admin=ep /sbin/ip

USER app

# Mutable Runtime Environment
RUN mkdir /tmp/app
ENV RELEASE_MUTABLE_DIR /tmp/app
ENV START_ERL_DATA /tmp/app/start_erl.data

# Start command
# NB 'myapp' should be replaced by your application name, as per mix.exs
ENTRYPOINT ["/opt/app/bin/acari_client", "console"]
#CMD ["/bin/sh"]
