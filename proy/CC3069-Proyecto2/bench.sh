#!/usr/bin/env bash
# Mide REPS ejecuciones por configuracion, toma la mediana y calcula
# Speedup = T_secuencial / T_paralelo y Eficiencia = Speedup / procesos.
# Uso: ./bench.sh [bits] [clave] [archivo]   (def. 22 4000000 texto.txt)
set -e
BITS=${1:-22}
KEY=${2:-4000000}
TXT=${3:-texto.txt}
REPS=${REPS:-5}

median() { sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
tiempo() { grep Tiempo | awk '{print $2}'; }

ts=$(for _ in $(seq "$REPS"); do ./bruteforce_des_secuencial "$BITS" "$KEY" "$TXT" | tiempo; done | median)
printf "Rango 2^%s, clave %s, mediana de %s ejecuciones\n" "$BITS" "$KEY" "$REPS"
printf "Secuencial: %s s\n\n" "$ts"
printf "%-10s %-14s %-10s %-10s\n" "Procesos" "Tiempo (s)" "Speedup" "Eficiencia"
for n in 2 3 4; do
    tp=$(for _ in $(seq "$REPS"); do mpirun -np "$n" ./bruteforce_des_mpi "$BITS" "$KEY" "$TXT" 2>/dev/null | tiempo; done | median)
    awk -v n="$n" -v ts="$ts" -v tp="$tp" \
        'BEGIN {printf "%-10d %-14s %-10.2f %-10.2f\n", n, tp, ts/tp, ts/tp/n}'
done
