#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$root_dir"

if [[ ! -f .env ]]; then
    cp .env.example .env
    printf '%s\n' 'Created .env from .env.example. Review its ports and network names, then run this script again.' >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

for command_name in docker openssl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

chown_path() {
    local owner=$1
    local path=$2

    if [[ $EUID -eq 0 ]]; then
        chown -R "$owner" "$path"
    else
        docker run --rm \
            -v "$root_dir:/work" \
            alpine:3.22 \
            chown -R "$owner" "/work/$path"
    fi
}

mkdir -p secrets
chmod 700 secrets

if [[ ! -s secrets/grafana-admin-password ]]; then
    openssl rand -base64 32 | tr -d '\n' > secrets/grafana-admin-password
fi

chown_path "$(id -u):472" secrets/grafana-admin-password
chmod 640 secrets/grafana-admin-password

ingress_network=${GRAFANA_INGRESS_NETWORK_NAME:-iyagi-grafana-ingress}
if ! docker network inspect "$ingress_network" >/dev/null 2>&1; then
    docker network create "$ingress_network" >/dev/null
fi

# The internal network is owned by compose; no pre-create needed. If a stale one
# exists from a previous run, remove it so compose can take ownership cleanly.
internal_network=${GRAFANA_INTERNAL_NETWORK_NAME:-iyagi-grafana-internal}
if docker network inspect "$internal_network" >/dev/null 2>&1; then
    if [[ -z $(docker network inspect "$internal_network" --format '{{range $k,$v := .Containers}}{{$k}} {{end}}') ]]; then
        docker network rm "$internal_network" >/dev/null
    fi
fi

# Bind-mounted config files must be readable by the container processes.
chmod 644 loki-config.yml grafana.ini
find grafana/provisioning -type f -exec chmod 644 {} +

# Data dirs are host bind mounts next to this script. Loki runs as UID 10001
# and Grafana as UID 472 inside their containers; chown the dirs so the
# containers can write. Idempotent and survives container deletion.
mkdir -p loki-data grafana-data
chown_path 10001:10001 loki-data
chown_path 472:472 grafana-data

compose_files=(-f docker-compose.yml)
if [[ -s secrets/telegram-bot-token && -n ${TELEGRAM_CHAT_ID:-} ]]; then
    chown_path "$(id -u):472" secrets/telegram-bot-token
    chmod 640 secrets/telegram-bot-token
    compose_files+=(-f docker-compose.telegram.yml)
fi

docker compose "${compose_files[@]}" up -d --wait

printf '\nGrafana is running on 127.0.0.1:%s.\n' "${GRAFANA_PORT:-13000}"
printf 'Reach it with: ssh -L %s:127.0.0.1:%s <host>\n' "${GRAFANA_PORT:-13000}" "${GRAFANA_PORT:-13000}"
printf 'Admin password is in secrets/grafana-admin-password.\n'
