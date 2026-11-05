#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

NODES=(mpi_maestro mpi_worker1 mpi_worker2)
HOSTS=(maestro worker1 worker2)

trust_nodes() {
    for i in "${!NODES[@]}"; do
        client_key=$(docker exec "${NODES[$i]}" cat /root/.ssh/id_ed25519.pub)
        host_key=$(docker exec "${NODES[$i]}" cat /root/.ssh/host_ed25519_key.pub)
        for node in "${NODES[@]}"; do
            docker exec "$node" mpi-trust "${HOSTS[$i]}" "$client_key" "$host_key"
        done
    done
}

copy_hostfile() {
    docker cp cluster_hosts mpi_maestro:/cluster/cluster_hosts
    docker exec mpi_maestro sed -i 's/\r$//' /cluster/cluster_hosts
}

case "${1:-}" in
    build)
        docker build -t mpi-cluster-image .
        ;;
    up)
        docker compose up -d --build --wait --wait-timeout 60
        trust_nodes
        ;;
    trust)
        trust_nodes
        ;;
    validate)
        docker exec mpi_maestro mpicc --version
        for peer in worker1 worker2; do
            docker exec mpi_maestro ssh "$peer" hostname
        done
        copy_hostfile
        docker exec mpi_maestro timeout 30s mpirun \
            --hostfile /cluster/cluster_hosts \
            --mca btl_tcp_if_include 10.42.0.0/24 \
            --mca oob_tcp_if_include 10.42.0.0/24 \
            -np 6 hostname
        coverage=$(docker exec mpi_maestro timeout 30s mpi-run \
            /cluster/cluster_hosts 10.42.0.0/24 3 10 999999)
        printf '%s\n' "$coverage"
        [[ "$coverage" == *"Candidatas probadas: 1024"* ]]
        recovery=$(docker exec mpi_maestro timeout 30s mpi-run \
            /cluster/cluster_hosts 10.42.0.0/24 6 16 12345)
        printf '%s\n' "$recovery"
        [[ "$recovery" == *"Clave encontrada: 12345"* ]]
        ;;
    run)
        copy_hostfile
        np=$(awk '!/^#/ { for (i=1;i<=NF;i++) if ($i ~ /^slots=/) { split($i,a,"="); s+=a[2] } } END { print s+0 }' cluster_hosts)
        docker exec mpi_maestro mpi-run /cluster/cluster_hosts \
            10.42.0.0/24 "$np" "${2:-22}" "${3:-4000000}"
        ;;
    ips)
        for node in "${NODES[@]}"; do
            printf '%s: ' "$node"
            docker exec "$node" hostname -I
        done
        ;;
    shell)
        docker exec -it mpi_maestro bash
        ;;
    down)
        docker compose down
        ;;
    *)
        echo "Uso: ./cluster.sh {build|up|trust|validate|run [bits] [clave]|ips|shell|down}" >&2
        exit 1
        ;;
esac
