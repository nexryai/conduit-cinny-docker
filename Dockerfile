# Build multirun
FROM rust:1-alpine as multirun-builder
WORKDIR /src

RUN apk add --no-cache git alpine-sdk
RUN git clone https://github.com/nicoburns/multirun/ . && git checkout v0.3.1
RUN cargo build --release

# Build Caddy
FROM golang:1-alpine as caddy-builder
WORKDIR /src

RUN apk add --no-cache git
RUN git clone https://github.com/caddyserver/caddy . && git checkout v2.7.6
RUN cd cmd/caddy && go build

# Build Conduit
FROM rust:1-alpine as conduit-builder
WORKDIR /src

ENV RUSTFLAGS="-C target-feature=-crt-static"
RUN apk add --no-cache git alpine-sdk clang-dev linux-headers
RUN git clone https://gitlab.com/famedly/conduit . && git switch master
RUN cargo build --release

# Build Cinny
FROM node:20.12.2-alpine3.18 as client-builder
WORKDIR /src

ENV NODE_OPTIONS=--max_old_space_size=4096
RUN apk add --no-cache git
RUN git clone https://github.com/cinnyapp/cinny/ . && git checkout v3.2.0
RUN npm ci
RUN npm run build

# Runtime
FROM alpine:3.20 as runtime
ARG USER_ID=587
ARG GROUP_ID=587

COPY --from=multirun-builder /src/target/release/multirun /usr/local/bin/multirun
COPY --from=caddy-builder /src/cmd/caddy/caddy /usr/local/bin/caddy
COPY --from=conduit-builder /src/target/release/conduit /usr/local/bin/conduit
COPY --from=client-builder /src/dist /var/cinny

RUN apk add --no-cache ca-certificates \
 && addgroup -g "${GROUP_ID}" app \
 && adduser -u "${USER_ID}" -G app -D -h /app app \
 && mkdir /app/caddy /app/data \
 && chown -R app:app /app

WORKDIR /app
USER app

COPY multirun.json /app/
COPY Caddyfile /etc/
CMD ["multirun"]
