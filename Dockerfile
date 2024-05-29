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
FROM nixos/nix:2.22.0 as conduit-builder
WORKDIR /src

RUN git clone https://gitlab.com/famedly/conduit . && git switch master
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
RUN echo "extra-substituters = https://crane.cachix.org" >> /etc/nix/nix.conf
RUN echo "extra-trusted-public-keys = crane.cachix.org-1:8Scfpmn9w+hGdXH/Q9tTLiYAE/2dnJYRJP7kl80GuRk=" >> /etc/nix/nix.conf
RUN echo "extra-substituters = https://nix-community.cachix.org" >> /etc/nix/nix.conf
RUN echo "extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" >> /etc/nix/nix.conf

RUN ./bin/nix-build-and-cache .#static-$(uname -m)-unknown-linux-musl --extra-experimental-features nix-command --extra-experimental-features flakes

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
COPY --from=conduit-builder /src/result/bin/conduit /usr/local/bin/conduit
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
