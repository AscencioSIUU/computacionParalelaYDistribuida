#!/usr/bin/env bash
set -euo pipefail
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cp "${1:?desktop.sh path requerido}" "$fixture/desktop.sh"
mkdir "$fixture/bin"
cat > "$fixture/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DESKTOP_TEST_CALLS"
DOCKER
chmod +x "$fixture/bin/docker"
export PATH="$fixture/bin:$PATH"
export DESKTOP_TEST_CALLS="$fixture/calls"

assert_call() {
    grep -Fxq "compose -p cc3069-desktop -f docker-compose.desktop.yml --profile master $1" "$DESKTOP_TEST_CALLS"
}

bash "$fixture/desktop.sh" master connect 192.168.1.150
assert_call 'exec -T master mpi-desktop connect 192.168.1.150 2222 1 1'
bash "$fixture/desktop.sh" master connect 192.168.1.151 2233 2 3
assert_call 'exec -T master mpi-desktop connect 192.168.1.151 2233 2 3'
bash "$fixture/desktop.sh" master trust-code public-code --verified 2
assert_call 'exec -T master mpi-desktop trust-code public-code 2'
bash "$fixture/desktop.sh" master inspect-code public-code 2
assert_call 'exec -T master mpi-desktop inspect-code public-code 2'
bash "$fixture/desktop.sh" master trust peer.public --verified 2
assert_call 'exec -T master mpi-desktop trust /tmp/mpi-peer.pub 2'
bash "$fixture/desktop.sh" master run
assert_call 'exec -T master mpi-desktop run 22 4000000 1'
bash "$fixture/desktop.sh" master run 16 50000 2 3
assert_call 'exec -T master mpi-desktop run 16 50000 2 3'
bash "$fixture/desktop.sh" master disconnect
assert_call 'exec -T master mpi-desktop disconnect'
bash "$fixture/desktop.sh" master disconnect 2
assert_call 'exec -T master mpi-desktop disconnect 2'
bash "$fixture/desktop.sh" master connect-all workers.csv
grep -Eq 'exec -T master mpi-desktop connect-all /tmp/mpi-workers-[0-9]+\.csv$' "$DESKTOP_TEST_CALLS"
grep -Eq 'exec -T master rm -f /tmp/mpi-workers-[0-9]+\.csv$' "$DESKTOP_TEST_CALLS"
if bash "$fixture/desktop.sh" master trust-code public-code; then exit 1; fi
echo 'PASS: Bash multi-worker arguments, legacy defaults, CSV cleanup and verified trust.'
