#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || ! "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    echo "Uso: mpi-trust HOST CLAVE_PUBLICA_CLIENTE CLAVE_PUBLICA_SERVIDOR" >&2
    exit 1
fi

peer=$1
client_key=$2
host_key=$3
umask 077
temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT
for key in "$client_key" "$host_key"; do
    if [[ "$key" != ssh-ed25519\ * || "$key" == *$'\n'* || "$key" == *$'\r'* ]]; then
        echo "Solo se aceptan claves publicas Ed25519 de una linea." >&2
        exit 1
    fi
    printf '%s\n' "$key" > "$temporary"
    ssh-keygen -lf "$temporary" >/dev/null
done

read -r host_type host_data _ <<< "$host_key"
entry="$peer $host_type $host_data"
if ssh-keygen -F "$peer" -f /root/.ssh/known_hosts > "$temporary"; then
    if ! grep -Fxq "$entry" "$temporary"; then
        echo "La clave de servidor para $peer cambio; verificar antes de reemplazarla." >&2
        exit 1
    fi
else
    printf '%s\n' "$entry" >> /root/.ssh/known_hosts
fi
if ! grep -Fxq "$client_key" /root/.ssh/authorized_keys; then
    printf '%s\n' "$client_key" >> /root/.ssh/authorized_keys
fi
echo "Confianza registrada: $peer"
