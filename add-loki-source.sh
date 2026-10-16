#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! $1 =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Usage: %s <source-name>\n' "$0" >&2
    exit 1
fi

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$root_dir"

source_name=$1
secret_path="secrets/loki-ingest-${source_name}"
htpasswd_path=generated/loki-ingest.htpasswd

mkdir -p secrets generated
chmod 700 secrets generated

if [[ ! -s $secret_path ]]; then
    openssl rand -base64 32 | tr -d '\n' > "$secret_path"
fi

password_hash=$(openssl passwd -apr1 -in "$secret_path")
touch "$htpasswd_path"
if grep -q "^${source_name}:" "$htpasswd_path"; then
    sed -i "s|^${source_name}:.*|${source_name}:${password_hash}|" "$htpasswd_path"
else
    printf '%s:%s\n' "$source_name" "$password_hash" >> "$htpasswd_path"
fi

chmod 600 "$secret_path" "$htpasswd_path"
printf 'Credential created for %s. Transfer %s to that source over an encrypted channel.\n' \
    "$source_name" "$secret_path"
