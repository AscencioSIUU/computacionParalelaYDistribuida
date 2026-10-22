#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Orquestador del cluster MPI local (CC3069 Proyecto 2, Parte 2).
# Levanta maestro + 2 workers en contenedores Docker sobre una red bridge y
# reproduce el flujo real del despliegue fisico: SSH sin contrasena entre nodos
# y mpirun --hostfile restringido a la subred del cluster.
#
#   ./cluster.sh build                 construye la imagen mpi-cluster-image
#   ./cluster.sh up                    levanta los 3 contenedores
#   ./cluster.sh validate              corre la tabla de validacion del enunciado
#   ./cluster.sh run [bits] [clave]    ataque distribuido (def. 22 4000000)
#   ./cluster.sh ips                   muestra la IP de cada contenedor
#   ./cluster.sh shell                 abre bash en el maestro
#   ./cluster.sh down                  destruye el cluster
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=mpi-cluster-image
SUBNET=10.42.0.0/24
MAESTRO=mpi_maestro
NODES=(mpi_maestro mpi_worker1 mpi_worker2)
HOSTFILE=cluster_hosts

total_slots() {
  awk '!/^#/ && /slots=/ { for (i=1;i<=NF;i++) if ($i ~ /^slots=/) { split($i,a,"="); s+=a[2] } } END { print s+0 }' "$HOSTFILE"
}

case "${1:-}" in
  build)
    docker build -t "$IMAGE" .
    ;;

  up)
    docker compose up -d
    echo "Esperando sshd en los nodos..."
    for n in "${NODES[@]}"; do
      until docker exec "$n" bash -c 'ss -ltn 2>/dev/null | grep -q ":22 "'; do sleep 0.3; done
      echo "  $n listo"
    done
    ;;

  validate)
    echo "== 1) mpicc --version =="
    docker run --rm "$IMAGE" mpicc --version | head -1
    echo
    echo "== 2) mpirun -np 2 echo (debe imprimir 2 veces) =="
    docker run --rm "$IMAGE" mpirun -np 2 echo "Proceso MPI ejecutado"
    echo
    echo "== 3) SSH maestro -> workers sin contrasena =="
    for w in worker1 worker2; do
      r=$(docker exec "$MAESTRO" ssh -o BatchMode=yes "$w" hostname)
      echo "maestro -> $w  OK (sin contrasena; hostname remoto: $r)"
    done
    ;;

  run)
    bits="${2:-22}"; key="${3:-4000000}"; np="$(total_slots)"
    docker cp "$HOSTFILE" "$MAESTRO":/cluster/cluster_hosts
    echo "Nodos del hostfile:"; grep -v '^#' "$HOSTFILE" | sed 's/^/  /'
    echo "mpirun -np $np, subred $SUBNET"; echo
    docker exec "$MAESTRO" mpirun --hostfile /cluster/cluster_hosts \
      --mca btl_tcp_if_include "$SUBNET" --mca oob_tcp_if_include "$SUBNET" \
      --mca btl tcp,self \
      -np "$np" /cluster/bruteforce "$bits" "$key"
    ;;

  ips)
    for n in "${NODES[@]}"; do
      printf '%-14s %s\n' "$n" "$(docker exec "$n" hostname -I | awk '{print $1}')"
    done
    ;;

  shell)
    docker exec -it "$MAESTRO" bash
    ;;

  down)
    docker compose down
    ;;

  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
