# Builds the Godot web export from source and serves it as static files.
# Self-contained: only needs this game_client/ directory as build context.

FROM debian:bookworm-slim AS build

ARG GODOT_VERSION=4.3
ARG GODOT_RELEASE=stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/godot
RUN wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip \
    && unzip -q Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip \
    && mv Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64 /usr/local/bin/godot \
    && rm Godot_v*.zip

# Export templates ship as one large archive; keep only the web templates.
RUN wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_export_templates.tpz \
    && mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE} \
    && unzip -q -j Godot_v*_export_templates.tpz 'templates/web_*' 'templates/version.txt' \
        -d /root/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE} \
    && rm Godot_v*_export_templates.tpz

WORKDIR /src
COPY . .
# Populate .godot/ import cache first; export on a fresh checkout can miss resources otherwise
RUN godot --headless --editor --quit || true
RUN mkdir -p build/web \
    && godot --headless --export-release "Web" build/web/index.html \
    && test -f build/web/index.wasm

FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/build/web /srv
COPY player_guide.html /srv/
