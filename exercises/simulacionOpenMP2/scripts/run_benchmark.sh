#!/usr/bin/env bash
# Ejecuta seq/pfor/sections con distintas cantidades de threads y guarda un CSV.
# Uso: ./run_benchmark.sh [N] [repeat] [threads_list]
set -euo pipefail
cd "$(dirname "$0")/.."

N=${1:-2000000}
REPEAT=${2:-30}
THREADS_LIST=${3:-"1 2 4 8"}
OUT=results/results.csv

make -s
mkdir -p results
BIN=bin/climate_sim
[ -f "${BIN}.exe" ] && BIN="${BIN}.exe"  # Windows/MinGW
echo "mode,N,repeat,threads,time,avgT,avgH,avgV" > "$OUT"

parse_and_append() {
    # lee la línea "mode=X N=Y repeat=Z threads=W time=T avgT=.. avgH=.. avgV=.." -> CSV
    local line="$1"
    local mode n rep th t at ah av
    mode=$(grep -o 'mode=[a-z]*' <<<"$line" | cut -d= -f2)
    n=$(grep -o 'N=[0-9]*' <<<"$line" | cut -d= -f2)
    rep=$(grep -o 'repeat=[0-9]*' <<<"$line" | cut -d= -f2)
    th=$(grep -o 'threads=[0-9]*' <<<"$line" | cut -d= -f2)
    t=$(grep -o 'time=[0-9.]*' <<<"$line" | cut -d= -f2)
    at=$(grep -o 'avgT=[0-9.-]*' <<<"$line" | cut -d= -f2)
    ah=$(grep -o 'avgH=[0-9.-]*' <<<"$line" | cut -d= -f2)
    av=$(grep -o 'avgV=[0-9.-]*' <<<"$line" | cut -d= -f2)
    echo "$mode,$n,$rep,$th,$t,$at,$ah,$av" >> "$OUT"
}

echo "== Secuencial (baseline, threads=1) =="
line=$("$BIN" seq "$N" "$REPEAT" 1)
echo "$line"
parse_and_append "$line"

for mode in pfor sections; do
    for t in $THREADS_LIST; do
        echo "== $mode threads=$t =="
        line=$("$BIN" "$mode" "$N" "$REPEAT" "$t")
        echo "$line"
        parse_and_append "$line"
    done
done

echo "Resultados guardados en $OUT"
