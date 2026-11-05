#!/usr/bin/env bash
set -euo pipefail

role=${MPI_DESKTOP_ROLE:-}
if [[ -z "$role" && -f /run/mpi-desktop-role ]]; then
    read -r role < /run/mpi-desktop-role
fi
[[ "$role" == master || "$role" == worker ]] || { echo "MPI_DESKTOP_ROLE requerido." >&2; exit 1; }
socket=/run/mpi-desktop.sock
subnet=10.77.0.0/30

require_master() {
    [[ "$role" == master ]] || { echo "Este comando requiere el maestro." >&2; exit 1; }
}

configure_link() {
    ip address replace "$1/30" dev tun0
    ip link set dev tun0 mtu 1400 up
}

case "${1:-}" in
    identity)
        cat /root/.ssh/id_ed25519.pub /root/.ssh/host_ed25519_key.pub
        ;;
    identity-code)
        cat /root/.ssh/id_ed25519.pub /root/.ssh/host_ed25519_key.pub | base64 -w 0
        printf '\n'
        ;;
    inspect-code|trust-code)
        [[ $# -eq 2 && "$2" =~ ^[A-Za-z0-9+/=]+$ ]] || { echo "Codigo publico invalido." >&2; exit 1; }
        file=$(mktemp)
        trap 'rm -f "$file"' EXIT
        printf '%s' "$2" | base64 --decode > "$file"
        ssh-keygen -lf "$file"
        if [[ "$1" == trust-code ]]; then
            /usr/local/bin/mpi-desktop.sh trust "$file"
        fi
        ;;
    fingerprints)
        ssh-keygen -lf "${2:-/root/.ssh/id_ed25519.pub}"
        if [[ $# -eq 1 ]]; then
            ssh-keygen -lf /root/.ssh/host_ed25519_key.pub
        fi
        ;;
    trust)
        [[ $# -eq 2 ]] || exit 1
        mapfile -t keys < <(tr -d '\r' < "$2")
        [[ ${#keys[@]} -eq 2 ]] || { echo "Se requieren dos claves publicas." >&2; exit 1; }
        if [[ "$role" == master ]]; then
            peer=mpi-worker
            address=10.77.0.2
        else
            peer=mpi-master
            address=10.77.0.1
        fi
        mpi-trust "$peer" "${keys[0]}" "${keys[1]}"
        mpi-trust "$address" "${keys[0]}" "${keys[1]}"
        ;;
    worker-link)
        [[ "$role" == worker ]] || exit 1
        configure_link 10.77.0.2
        exec sleep infinity
        ;;
    connect)
        require_master
        [[ $# -eq 3 && "$2" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ && "$3" =~ ^[0-9]+$ ]] || exit 1
        (( 10#$3 >= 1 && 10#$3 <= 65535 )) || exit 1
        if [[ -S "$socket" ]] && ssh -S "$socket" -O check mpi-worker 2>/dev/null; then
            echo "Ya existe un tunel. disconnect permite cambiar de destino." >&2
            exit 1
        fi
        rm -f "$socket"
        ssh -f -M -S "$socket" -o ExitOnForwardFailure=yes \
            -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
            -o HostKeyAlias=mpi-worker -o Tunnel=point-to-point \
            -w 0:0 -p "$3" "$2" /usr/local/bin/mpi-desktop.sh worker-link
        configure_link 10.77.0.1
        ping -c 3 -W 3 10.77.0.2
        ;;
    disconnect)
        require_master
        if [[ -S "$socket" ]]; then
            ssh -S "$socket" -O exit mpi-worker
        fi
        ;;
    status)
        ip -brief address show tun0
        if [[ "$role" == master ]]; then
            ping -c 1 -W 3 10.77.0.2
            ssh 10.77.0.2 hostname
        fi
        ;;
    validate)
        require_master
        [[ "$(dpkg --print-architecture)" == amd64 ]]
        [[ "$(ssh 10.77.0.2 dpkg --print-architecture)" == amd64 ]]
        ip route get 10.77.0.2
        file=$(mktemp)
        trap 'rm -f "$file"' EXIT
        printf '10.77.0.1 slots=1 max_slots=1\n10.77.0.2 slots=1 max_slots=1\n' > "$file"
        timeout 30s mpirun --hostfile "$file" \
            --mca btl_tcp_if_include "$subnet" --mca oob_tcp_if_include "$subnet" \
            -np 2 hostname
        recovery=$(timeout 45s mpi-run "$file" "$subnet" 2 16 50000)
        printf '%s\n' "$recovery"
        [[ "$recovery" == *"Clave encontrada: 50000"* ]]
        coverage=$(timeout 45s mpi-run "$file" "$subnet" 2 10 999999)
        printf '%s\n' "$coverage"
        [[ "$coverage" == *"Candidatas probadas: 1024"* ]]
        ;;
    run)
        require_master
        [[ $# -eq 5 && "$4" =~ ^[1-9][0-9]*$ && "$5" =~ ^[1-9][0-9]*$ ]] || exit 1
        file=$(mktemp)
        trap 'rm -f "$file"' EXIT
        printf '10.77.0.1 slots=%s max_slots=%s\n10.77.0.2 slots=%s max_slots=%s\n' \
            "$4" "$4" "$5" "$5" > "$file"
        mpi-run "$file" "$subnet" "$(( $4 + $5 ))" "$2" "$3"
        ;;
    *)
        echo "Uso: mpi-desktop {identity|identity-code|inspect-code CODIGO|trust-code CODIGO|fingerprints [archivo]|trust archivo|connect IP PUERTO|disconnect|status|validate|run BITS CLAVE SLOTS_MAESTRO SLOTS_WORKER}" >&2
        exit 1
        ;;
esac
