#!/usr/bin/env bash
set -euo pipefail

umask 077
mkdir -p /run/sshd /root/.ssh
chmod 700 /root/.ssh
for name in id_ed25519 host_ed25519_key; do
    if [[ ! -f "/root/.ssh/$name" ]]; then
        ssh-keygen -q -t ed25519 -N "" -f "/root/.ssh/$name"
    fi
done
touch /root/.ssh/authorized_keys /root/.ssh/known_hosts
chmod 600 /root/.ssh/authorized_keys /root/.ssh/known_hosts
if [[ -n "${MPI_DESKTOP_ROLE:-}" ]]; then
    [[ "$MPI_DESKTOP_ROLE" == master || "$MPI_DESKTOP_ROLE" == worker ]] || exit 1
    printf '%s\n' "$MPI_DESKTOP_ROLE" > /run/mpi-desktop-role
fi
exec "$@"
