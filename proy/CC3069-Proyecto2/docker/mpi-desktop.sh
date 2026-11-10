#!/usr/bin/env bash
set -euo pipefail

role=${MPI_DESKTOP_ROLE:-}
if [[ -z "$role" && -f /run/mpi-desktop-role ]]; then
    read -r role < /run/mpi-desktop-role
fi
[[ "$role" == master || "$role" == worker ]] || { echo "MPI_DESKTOP_ROLE requerido." >&2; exit 1; }
state=/run/mpi-desktop
subnet=10.77.0.0/16
master_address=10.77.0.1
mkdir -p "$state/workers"
umask 077

require_master() {
    [[ "$role" == master ]] || { echo "Este comando requiere el maestro." >&2; exit 1; }
}

worker_id() {
    [[ "$1" =~ ^[0-9]{1,3}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 254 )) || {
        echo "WorkerId debe estar entre 1 y 254." >&2
        return 1
    }
    id=$((10#$1))
    peer=mpi-worker
    if (( id != 1 )); then peer="mpi-worker-$id"; fi
    address="10.77.$id.2"
    socket="$state/$id.sock"
}

worker_parameters() {
    worker_id "$1"
    [[ "$2" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ &&
       "$3" =~ ^[0-9]{1,5}$ && "$4" =~ ^[0-9]{1,2}$ ]] &&
        (( 10#$3 >= 1 && 10#$3 <= 65535 && 10#$4 >= 1 && 10#$4 <= 64 )) || {
        echo "Se requiere una direccion, un puerto entre 1 y 65535 y slots entre 1 y 64." >&2
        return 1
    }
}

load_workers() {
    mapfile -t workers < <(find "$state/workers" -maxdepth 1 -type f -printf '%f\n' | sort -n)
}

configure_link() {
    ip address replace "$1/30" dev "$2" &&
        ip link set dev "$2" mtu 1400 up
}

disconnect_worker() {
    worker_id "$1"
    if [[ -S "$socket" ]]; then
        ssh -S "$socket" -O exit "$peer" 2>/dev/null || true
    fi
    if ! ip link delete "tun$id" 2>/dev/null && ip link show "tun$id" >/dev/null 2>&1; then
        echo "No se pudo eliminar tun$id." >&2
        return 1
    fi
    rm -f "$socket" "$state/workers/$id"
}

connect_worker() {
    local requested_id=$1 endpoint=$2 port=$3 slots=$4 other_id other_endpoint other_port other_slots
    worker_parameters "$requested_id" "$endpoint" "$port" "$slots"
    requested_id=$id
    load_workers
    for other_id in "${workers[@]}"; do
        read -r other_endpoint other_port other_slots < "$state/workers/$other_id"
        if [[ "$other_id" != "$requested_id" && "$endpoint $((10#$port))" == "$other_endpoint $other_port" ]]; then
            echo "El destino ya pertenece al worker $other_id." >&2
            return 1
        fi
    done
    if [[ -S "$socket" ]] && ssh -S "$socket" -O check "$peer" 2>/dev/null; then
        echo "El worker $id ya tiene un tunel. disconnect $id permite cambiarlo." >&2
        return 1
    fi
    disconnect_worker "$id"
    local forwarding
    read -r forwarding < /proc/sys/net/ipv4/ip_forward
    [[ "$forwarding" == 1 ]] || { echo "El maestro requiere net.ipv4.ip_forward=1." >&2; return 1; }
    if ! ip link show mpi0 >/dev/null 2>&1; then ip link add mpi0 type dummy; fi
    ip address replace "$master_address/32" dev mpi0
    ip link set dev mpi0 up
    ip route replace unreachable "$subnet"
    if ! ssh -f -M -S "$socket" -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
        -o HostKeyAlias="$peer" -o Tunnel=point-to-point \
        -w "$id:0" -p "$((10#$port))" "$endpoint" /usr/local/bin/mpi-desktop.sh worker-link "$id" 9>&-; then
        disconnect_worker "$requested_id"
        return 1
    fi
    if ! configure_link "10.77.$id.1" "tun$id" || ! ping -c 3 -W 3 "$address"; then
        disconnect_worker "$requested_id"
        return 1
    fi
    printf '%s %s %s\n' "$endpoint" "$((10#$port))" "$((10#$slots))" > "$state/workers/$id"
}

prepare_hosts() {
    local master_slots=$1 override=${2:-} current_id slots endpoint port
    [[ "$master_slots" =~ ^[1-9][0-9]?$ ]] && (( master_slots <= 64 )) || return 1
    if [[ -n "$override" ]]; then
        [[ "$override" =~ ^[1-9][0-9]?$ ]] && (( override <= 64 )) || return 1
    fi
    load_workers
    (( ${#workers[@]} > 0 )) || { echo "No hay workers conectados." >&2; return 1; }
    printf '%s slots=%s max_slots=%s\n' "$master_address" "$master_slots" "$master_slots" > "$state/hosts"
    printf 'Host *\n    BatchMode yes\n    StrictHostKeyChecking yes\n    ConnectTimeout 5\n    IdentityFile /root/.ssh/id_ed25519\n    IdentitiesOnly yes\n' > "$state/ssh_config"
    processes=$master_slots
    for current_id in "${workers[@]}"; do
        worker_id "$current_id"
        ssh -S "$socket" -O check "$peer" 2>/dev/null || {
            echo "El worker $id esta desconectado. Se requiere reconnectar o disconnect $id." >&2
            return 1
        }
        read -r endpoint port slots < "$state/workers/$id"
        slots=${override:-$slots}
        printf '%s slots=%s max_slots=%s\n' "$address" "$slots" "$slots" >> "$state/hosts"
        printf 'Host %s\n    HostKeyAlias %s\n' "$address" "$peer" >> "$state/ssh_config"
        processes=$((processes + slots))
    done
}

case "${1:-}" in
    connect|connect-all|disconnect|status|validate|run)
        if [[ "$role" == master ]]; then
            exec 9>"$state/lock"
            flock -x 9
        fi
        ;;
esac

case "${1:-}" in
    identity)
        cat /root/.ssh/id_ed25519.pub /root/.ssh/host_ed25519_key.pub
        ;;
    identity-code)
        cat /root/.ssh/id_ed25519.pub /root/.ssh/host_ed25519_key.pub | base64 -w 0
        printf '\n'
        ;;
    inspect-code|trust-code)
        [[ $# -ge 2 && $# -le 3 && "$2" =~ ^[A-Za-z0-9+/=]+$ ]] || { echo "Codigo publico invalido." >&2; exit 1; }
        worker_id "${3:-1}"
        file=$(mktemp)
        trap 'rm -f "$file"' EXIT
        printf '%s' "$2" | base64 --decode > "$file"
        ssh-keygen -lf "$file"
        if [[ "$1" == trust-code ]]; then
            /usr/local/bin/mpi-desktop.sh trust "$file" "$id"
        fi
        ;;
    fingerprints)
        ssh-keygen -lf "${2:-/root/.ssh/id_ed25519.pub}"
        if [[ $# -eq 1 ]]; then
            ssh-keygen -lf /root/.ssh/host_ed25519_key.pub
        fi
        ;;
    trust)
        [[ $# -ge 2 && $# -le 3 ]] || exit 1
        worker_id "${3:-1}"
        mapfile -t keys < <(tr -d '\r' < "$2")
        [[ ${#keys[@]} -eq 2 ]] || { echo "Se requieren dos claves publicas." >&2; exit 1; }
        if [[ "$role" == master ]]; then
            mpi-trust "$peer" "${keys[0]}" "${keys[1]}"
        else
            mpi-trust mpi-master "${keys[0]}" "${keys[1]}"
            mpi-trust "$master_address" "${keys[0]}" "${keys[1]}"
        fi
        ;;
    worker-link)
        [[ "$role" == worker ]] || exit 1
        [[ $# -eq 2 ]] || exit 1
        worker_id "$2"
        configure_link "$address" tun0
        ip route replace "$subnet" dev tun0
        exec sleep infinity
        ;;
    connect)
        require_master
        [[ $# -ge 3 && $# -le 5 ]] || exit 1
        connect_worker "${4:-1}" "$2" "$3" "${5:-1}"
        ;;
    connect-all)
        require_master
        [[ $# -eq 2 ]] || exit 1
        file=$(mktemp)
        trap 'rm -f "$file"' EXIT
        declare -A seen_ids=() seen_endpoints=()
        exec 3< "$2"
        IFS= read -r header <&3
        [[ "${header%$'\r'}" == 'Id,Address,Port,Slots' ]] || { echo "Cabecera CSV requerida: Id,Address,Port,Slots" >&2; exit 1; }
        while IFS= read -r line <&3 || [[ -n "$line" ]]; do
            line=${line%$'\r'}
            [[ -n "$line" ]] || continue
            [[ "$line" =~ ^([0-9]+),([^,]+),([0-9]+),([0-9]+)$ ]] || { echo "Fila CSV invalida." >&2; exit 1; }
            worker_parameters "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"
            IFS=, read -r _ endpoint port slots <<< "$line"
            port=$((10#$port))
            slots=$((10#$slots))
            [[ ! -v seen_ids[$id] && ! -v seen_endpoints[$endpoint:$port] ]] || { echo "WorkerId o destino duplicado." >&2; exit 1; }
            seen_ids[$id]=1
            seen_endpoints[$endpoint:$port]=1
            printf '%s %s %s %s\n' "$id" "$endpoint" "$port" "$slots" >> "$file"
        done
        [[ -s "$file" ]] || { echo "La lista de workers esta vacia." >&2; exit 1; }
        while read -r current_id endpoint port slots; do
            worker_id "$current_id"
            if [[ -f "$state/workers/$id" && -S "$socket" ]] &&
                ssh -S "$socket" -O check "$peer" 2>/dev/null; then
                read -r old_endpoint old_port _ < "$state/workers/$id"
                [[ "$endpoint $port" == "$old_endpoint $old_port" ]] || { echo "disconnect $id es requerido para cambiar su destino." >&2; exit 1; }
                printf '%s %s %s\n' "$endpoint" "$port" "$slots" > "$state/workers/$id"
                echo "Worker $id ya conectado."
            else
                connect_worker "$current_id" "$endpoint" "$port" "$slots"
            fi
        done < "$file"
        ;;
    disconnect)
        require_master
        [[ $# -le 2 ]] || exit 1
        if [[ $# -eq 2 ]]; then
            disconnect_worker "$2"
        else
            load_workers
            for current_id in "${workers[@]}"; do disconnect_worker "$current_id"; done
        fi
        ;;
    status)
        if [[ "$role" == master ]]; then
            prepare_hosts 1
            for current_id in "${workers[@]}"; do
                worker_id "$current_id"
                echo "Worker $id: $address"
                ping -c 1 -W 3 "$address"
                ssh -F "$state/ssh_config" "$address" hostname
            done
        else
            ip -brief address show tun0
        fi
        ;;
    validate)
        require_master
        prepare_hosts 1 1
        [[ "$(dpkg --print-architecture)" == amd64 ]]
        for current_id in "${workers[@]}"; do
            worker_id "$current_id"
            [[ "$(ssh -F "$state/ssh_config" "$address" dpkg --print-architecture)" == amd64 ]]
            ssh -F "$state/ssh_config" "$address" ping -c 1 -W 3 "$master_address"
            for other_id in "${workers[@]}"; do
                if [[ "$current_id" != "$other_id" ]]; then
                    ssh -F "$state/ssh_config" "$address" ping -c 1 -W 3 "10.77.$other_id.2"
                fi
            done
        done
        export MPI_DESKTOP_SSH_CONFIG="$state/ssh_config"
        timeout 30s mpirun --hostfile "$state/hosts" \
            --mca plm_rsh_agent "ssh -F $MPI_DESKTOP_SSH_CONFIG" \
            --mca plm_rsh_no_tree_spawn 1 --mca routed direct \
            --mca btl_tcp_if_include "$subnet" --mca oob_tcp_if_include "$subnet" \
            -np "$processes" hostname
        recovery=$(timeout 45s mpi-run "$state/hosts" "$subnet" "$processes" 16 50000)
        printf '%s\n' "$recovery"
        [[ "$recovery" == *"Clave encontrada: 50000"* ]]
        coverage=$(timeout 45s mpi-run "$state/hosts" "$subnet" "$processes" 10 999999)
        printf '%s\n' "$coverage"
        [[ "$coverage" == *"Candidatas probadas: 1024"* ]]
        ;;
    run)
        require_master
        [[ $# -ge 4 && $# -le 5 ]] || exit 1
        prepare_hosts "$4" "${5:-}"
        export MPI_DESKTOP_SSH_CONFIG="$state/ssh_config"
        mpi-run "$state/hosts" "$subnet" "$processes" "$2" "$3"
        ;;
    *)
        echo "Uso: mpi-desktop {identity|identity-code|inspect-code CODIGO [ID]|trust-code CODIGO [ID]|fingerprints [archivo]|trust archivo [ID]|connect IP PUERTO [ID] [SLOTS]|connect-all CSV|disconnect [ID]|status|validate|run BITS CLAVE SLOTS_MAESTRO [SLOTS_WORKER]}" >&2
        exit 1
        ;;
esac
