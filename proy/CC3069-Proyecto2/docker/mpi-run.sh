#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 5 || ! "$3" =~ ^[1-9][0-9]*$ ]]; then
    echo "Uso: mpi-run HOSTFILE SUBRED PROCESOS [BITS] [CLAVE]" >&2
    exit 1
fi

hostfile=$(mktemp)
trap 'rm -f "$hostfile"' EXIT
tr -d '\r' < "$1" > "$hostfile"
rsh_options=()
if [[ -n "${MPI_DESKTOP_SSH_CONFIG:-}" ]]; then
    rsh_options=(--mca plm_rsh_agent "ssh -F $MPI_DESKTOP_SSH_CONFIG"
        --mca plm_rsh_no_tree_spawn 1 --mca routed direct)
fi
mpirun --hostfile "$hostfile" \
    "${rsh_options[@]}" \
    --mca btl tcp,self \
    --mca btl_tcp_if_include "$2" \
    --mca oob_tcp_if_include "$2" \
    --mca btl_tcp_port_min_v4 20000 \
    --mca btl_tcp_port_range_v4 100 \
    --mca oob_tcp_dynamic_ipv4_ports 21000-21099 \
    -np "$3" "${BRUTEFORCE:-/cluster/bruteforce}" "${4:-22}" "${5:-4000000}"
