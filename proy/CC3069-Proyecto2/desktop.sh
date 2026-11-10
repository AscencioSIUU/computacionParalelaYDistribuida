#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

role=${1:-}
command=${2:-status}
[[ "$role" == master || "$role" == worker ]] || { echo "Uso: bash desktop.sh {master|worker} COMANDO [ARGUMENTOS]" >&2; exit 1; }

compose() {
    docker compose -p cc3069-desktop -f docker-compose.desktop.yml --profile "$role" "$@"
}

node() {
    compose exec -T "$role" mpi-desktop "$@"
}

case "$command" in
    up)
        export MPI_BIND_IP=${3:-127.0.0.1}
        export MPI_SSH_PORT=${4:-2222}
        compose up -d --build --wait --wait-timeout 90 "$role"
        ;;
    identity)
        node fingerprints
        printf 'Codigo publico: '
        node identity-code
        ;;
    inspect-code|trust-code)
        [[ $# -ge 3 ]] || { echo "Se requiere el codigo publico del otro nodo." >&2; exit 1; }
        if [[ "$command" == trust-code && "${4:-}" != --verified ]]; then
            echo "Las dos huellas deben verificarse con el propietario antes de usar --verified." >&2
            exit 1
        fi
        if [[ "$command" == trust-code ]]; then node "$command" "$3" "${5:-1}"
        else node "$command" "$3" "${4:-1}"; fi
        ;;
    inspect|trust)
        [[ $# -ge 3 ]] || { echo "Se requiere el archivo publico del otro nodo." >&2; exit 1; }
        if [[ "$command" == trust && "${4:-}" != --verified ]]; then
            echo "Las dos huellas deben verificarse con el propietario antes de usar --verified." >&2
            exit 1
        fi
        compose cp "$3" "$role:/tmp/mpi-peer.pub"
        node fingerprints /tmp/mpi-peer.pub
        if [[ "$command" == trust ]]; then node trust /tmp/mpi-peer.pub "${5:-1}"; fi
        ;;
    connect)
        [[ $# -ge 3 ]] || exit 1
        node connect "$3" "${4:-2222}" "${5:-1}" "${6:-1}"
        ;;
    connect-all)
        [[ $# -eq 3 ]] || { echo "Se requiere un CSV con Id,Address,Port,Slots." >&2; exit 1; }
        remote="/tmp/mpi-workers-$$.csv"
        compose cp "$3" "$role:$remote"
        trap 'compose exec -T "$role" rm -f "$remote"' EXIT
        node connect-all "$remote"
        ;;
    run)
        if [[ $# -ge 6 ]]; then node run "${3:-22}" "${4:-4000000}" "${5:-1}" "$6"
        else node run "${3:-22}" "${4:-4000000}" "${5:-1}"; fi
        ;;
    disconnect)
        if [[ $# -ge 3 ]]; then node disconnect "$3"
        else node disconnect; fi
        ;;
    status|validate)
        node "$command"
        ;;
    down)
        compose down
        ;;
    *)
        echo "Comando desconocido: $command" >&2
        exit 1
        ;;
esac
