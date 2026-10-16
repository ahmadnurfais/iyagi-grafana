# Iyagi Grafana

Central log storage and dashboards for Iyagi services.

## Components

| Component | Purpose |
| --- | --- |
| Grafana | Dashboards, log search, and alerts |
| Loki | Log ingestion, storage, and LogQL queries |
| Loki readiness check | Delays Grafana startup until Loki accepts requests |

The stack stores data in `grafana-data/` and `loki-data/`. Both directories survive container
replacement.

## Setup

Requirements: Docker Engine with Compose v2 and OpenSSL.

```sh
cp .env.example .env
nano .env
./init-grafana.sh
```

The initialization script creates the Grafana administrator password, prepares the data directories,
creates the generic local ingestion network, then starts the stack.

Check the services:

```sh
docker compose ps
```

Expected services:

```text
iyagi-grafana
iyagi-loki
iyagi-loki-ready
```

## Grafana Access

Grafana binds to `127.0.0.1:13000`. Open an SSH tunnel from the operator workstation:

```sh
ssh -L 13000:127.0.0.1:13000 <observability-host>
```

Open:

```text
http://127.0.0.1:13000
```

Sign in as `admin`. The password is stored in:

```text
secrets/grafana-admin-password
```

## Log Ingestion

### Local Collectors

A collector on the same Docker host can join `iyagi-grafana-ingress` and send logs to:

```text
http://loki:3100/loki/api/v1/push
```

The base stack always provides this network endpoint. Nginx and TLS are not required for local
Docker-network traffic.

### Remote Collectors

Use an authenticated HTTPS endpoint when a collector runs on another server. Loki has no built-in
authentication, so a host reverse proxy must protect the write endpoint.

The repository includes an example:

```text
nginx/loki-ingest.conf.example
```

The example exposes only:

```text
POST /loki/api/v1/push
```

It proxies to Loki on:

```text
http://127.0.0.1:13100
```

Create a credential for each remote source:

```sh
./add-loki-source.sh <source-name>
```

Run the command once per source, for example:

```sh
./add-loki-source.sh lldap
./add-loki-source.sh backend
```

Each run creates or rotates:

```text
secrets/loki-ingest-<source-name>
generated/loki-ingest.htpasswd
```

Install the generated htpasswd file and adapt the example to the host reverse proxy. DNS, TLS, and
reverse-proxy management remain host-level operations. The container stack does not require Nginx
when all collectors use the local Docker network.

## Retention

Set Loki retention in `.env`:

```dotenv
LOKI_RETENTION_PERIOD=8760h
```

`8760h` keeps one year of logs. Loki deletes data by age, not by available disk space. Monitor the
filesystem that contains `loki-data/`.

## Telegram Alerts

Telegram is optional. Set the chat ID in `.env`:

```dotenv
TELEGRAM_CHAT_ID=-1000000000000
```

Store the bot token in:

```text
secrets/telegram-bot-token
```

Run `./init-grafana.sh` again. The script enables `docker-compose.telegram.yml` when both values
exist.

## Backup

Stop writes before copying the data directories:

```sh
docker compose stop grafana loki
tar -czf iyagi-grafana-backup.tar.gz grafana-data loki-data .env secrets
docker compose start loki grafana
```

Store the archive outside the observability server and protect it as a credential-bearing backup.

## Upgrade

Review Grafana and Loki release notes before changing image versions. Then run:

```sh
docker compose pull
docker compose config --quiet
docker compose up -d --wait
docker compose logs --since 10m grafana loki
```
