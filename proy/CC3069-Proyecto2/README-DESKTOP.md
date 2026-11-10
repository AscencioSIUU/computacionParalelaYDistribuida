# Docker Desktop MPI workers on Windows and Mac

This setup uses one coordinator and one or more workers, each running Docker
Desktop with Linux containers. No separate Linux VM, host networking, VPN account, or router port
forwarding is required.

All containers use `linux/amd64`. Apple Silicon runs that image under emulation.
The master opens an independent encrypted SSH tunnel to each worker and routes
traffic between workers. MPI uses `10.77.0.1` for the master and `10.77.ID.2` for
each worker, not Docker bridge addresses or the computers' Wi-Fi addresses.

## Requirements

- All computers run the same project files and Docker Desktop with Linux
  containers. Apple Silicon must support amd64 emulation in Docker Desktop.
- The network permits direct TCP connections between participants. Being on
  the same Wi-Fi does not bypass guest-network or campus-network isolation.
- The Docker engine permits `/dev/net/tun` and the container-only `NET_ADMIN`
  capability. Docker policies or Enhanced Container Isolation can block this
  configuration. Changes to an organization's security policy require its approval.
- The private range `10.77.0.0/16` must not overlap a required network or VPN.
- Each worker publishes TCP `2222`, bound to its chosen LAN IP.
  The Windows master publishes no ports and needs no new inbound firewall rule.

The tunnel permissions apply inside the containers, not to Windows or macOS.
`--privileged` is not used. The Mac firewall must allow the Docker worker's
incoming connection, preferably restricted to the master's LAN IP. The firewall
must remain enabled. No inbound MPI port ranges are needed for this setup.

## 1. Windows coordinator

All build inputs and launchers belong in the repository. All participants run
the same committed revision from the project directory
`proy/CC3069-Proyecto2`. No ZIP, prebuilt image transfer, or copied key file is
required. New changes must be committed and made available in the shared
repository before the classmate updates their checkout.

From the project directory in PowerShell 7:

```powershell
.\desktop.ps1 up
.\desktop.ps1 identity
```

The identity command prints two fingerprints and a single public identity code.
That code contains only the two public keys, encoded for convenient copying.
It is not a password or a private key.
The master is ready for key exchange, but the tunnel is not connected yet.

## 2. Mac worker

The Mac needs the same updated repository revision. Commands run from the
project directory, which contains `Dockerfile` and `desktop.sh`. Both participants
can compare `git rev-parse --short HEAD` before starting.

The Wi-Fi address is normally available with:

```bash
ipconfig getifaddr en0
```

If that command is empty, the active interface and its IP appear in
System Settings, Network. The command below uses an example address that must
be replaced with the Mac's actual LAN IPv4 address:

```bash
bash ./desktop.sh worker up 10.15.36.20
bash ./desktop.sh worker identity
```

The first build can take several minutes under emulation. The worker must finish
healthy before continuing. Its `identity` command prints the worker's public
identity code and both fingerprints.

If the Mac reports an unavailable tunnel device or `Operation not permitted`,
the engine cannot run this setup as configured. That error must be resolved
before a distributed test; successful local MPI alone is not sufficient.

## 3. Pairing without file transfer

### Windows worker alternative

A Windows computer can take the worker role instead of the Mac. From the project
directory, PowerShell must run as administrator for the initial setup:

```powershell
.\worker.ps1
```

The script starts Docker Desktop when needed, requires Linux containers, builds
and starts only the worker, and checks its health and LAN SSH port. Docker Desktop
must already be installed with its Windows and WSL prerequisites configured.
The first image build requires internet access and can take several minutes.

The active LAN IPv4 is selected from the interface with a default gateway. If
several addresses qualify, or a specific interface is needed:

```powershell
.\worker.ps1 -BindAddress 192.168.1.150
```

The script creates or updates only `CC3069-MPI-Worker-2222`. Its inbound TCP rule
allows `LocalSubnet` on the selected LAN address and interface, including when
Windows labels the network Public. The firewall stays enabled and the network
profile does not change. No Windows SSH server, Docker API port, router forwarding,
or inbound MPI port range is opened. More computers on that local subnet do not
need additional firewall entries. Any computer on that subnet can reach the SSH
port, but only explicitly trusted public keys can authenticate.

Preview and read-only checks do not require administrator privileges:

```powershell
.\worker.ps1 -WhatIf
.\worker.ps1 -CheckOnly
```

The isolated setup tests run without administrator privileges or Docker changes:

```powershell
.\tests\worker-setup.ps1
```

`-CheckOnly` fails if the worker, its published port, or its firewall rule is not
ready. The local TCP check cannot prove that another physical computer can
connect. On the coordinator, `Test-NetConnection WORKER_LAN_IP -Port 2222` checks
network reachability before the SSH trust exchange.

For a custom SSH port, both setup and checks use `-Port`, and the coordinator's
`connect` command must use the same port. A new port creates a separate firewall
rule. After a LAN address change, setup must run again.
Shutdown does not remove the rule or the worker's persistent identity:

```powershell
.\desktop.ps1 down -Role worker
Remove-NetFirewallRule -Name 'CC3069-MPI-Worker-2222'
```

The worker prints its public identity with:

```powershell
.\desktop.ps1 identity -Role worker
```

The pairing commands below apply to a Windows worker with `-Role worker`:

```powershell
.\desktop.ps1 inspect -Role worker -PeerCode 'MASTER_PUBLIC_CODE'
.\desktop.ps1 trust -Role worker -PeerCode 'MASTER_PUBLIC_CODE' -Verified
```

The worker never runs `connect`, `validate`, or `run`; those belong to the master.
The same worker setup runs on each Windows participant. Workers need no local
ID setting; the coordinator assigns their tunnel IDs when connecting.

### Identity exchange

Each participant copies the public identity code from `identity` to the other
participant. The code is one line after `Codigo publico:`. Only that line's
value is copied, without the label. No files are transferred.
Private keys remain in per-node Docker volumes and must never enter Git or be
copied or sent. Node identities are generated at runtime, not shared in the repo.

The received fingerprints can be inspected before trust is granted:

Windows:

```powershell
.\desktop.ps1 inspect -PeerCode 'WORKER_PUBLIC_CODE'
```

Mac:

```bash
bash ./desktop.sh worker inspect-code 'MASTER_PUBLIC_CODE'
```

Both fingerprints must match the owner's `identity` output through an
independent check, such as direct comparison with the owner's screen.
After that verification:

Windows:

```powershell
.\desktop.ps1 trust -PeerCode 'WORKER_PUBLIC_CODE' -Verified
```

Mac:

```bash
bash ./desktop.sh worker trust-code 'MASTER_PUBLIC_CODE' --verified
```

The tool rejects a changed server identity instead of silently accepting it.
Trust grants the classmate remote access as root inside the project container;
only the intended classmate's verified keys belong here.
The placeholders above must be replaced with the actual complete public codes.
Copying the same repository does not establish SSH trust automatically.

## 4. Connection and test from Windows

### One worker

The master's command uses the worker's real LAN IPv4 address. Existing commands
without `-WorkerId` select worker 1:

```powershell
.\desktop.ps1 connect -PeerAddress 10.15.36.20
.\desktop.ps1 status
.\desktop.ps1 validate
.\desktop.ps1 run -Bits 22 -Key 4000000
```

Expected validation results:

- Ping succeeds through the worker's tunnel.
- SSH returns `mpi-worker`.
- All nodes report the `amd64` package architecture.
- Process placement prints `mpi-master` and `mpi-worker`.
- The short search recovers key `50000`.
- The exhaustive search tests exactly `1024` candidates.

`run` uses one master process and each worker's configured slots. More processes can be selected
without exceeding the CPU allocated to each Docker engine:

```powershell
.\desktop.ps1 run -MasterSlots 2 -WorkerSlots 1
```

`-WorkerSlots` on `run` overrides the slots for every connected worker. When
omitted, the slots supplied to `connect` or listed in the CSV are retained.

### Several workers

Every worker needs a stable, unique ID from `1` to `254`. The first worker keeps
the existing `mpi-worker` identity alias; other aliases include the ID. Each
worker independently verifies and trusts the master's public code using the
commands above. Workers do not need to exchange keys with one another.

On the coordinator, each worker's two fingerprints must be independently checked
before its public code is trusted under its ID:

```powershell
.\desktop.ps1 inspect -WorkerId 1 -PeerCode 'WORKER_1_PUBLIC_CODE'
.\desktop.ps1 trust -WorkerId 1 -PeerCode 'WORKER_1_PUBLIC_CODE' -Verified
.\desktop.ps1 inspect -WorkerId 2 -PeerCode 'WORKER_2_PUBLIC_CODE'
.\desktop.ps1 trust -WorkerId 2 -PeerCode 'WORKER_2_PUBLIC_CODE' -Verified
```

Individual connections can assign different process counts:

```powershell
.\desktop.ps1 connect -WorkerId 1 -PeerAddress 192.168.1.150 -WorkerSlots 1
.\desktop.ps1 connect -WorkerId 2 -PeerAddress 192.168.1.151 -WorkerSlots 2
.\desktop.ps1 validate
.\desktop.ps1 run -Bits 22 -Key 4000000
```

This example starts four MPI processes: one on the master, one on worker 1, and
two on worker 2. Slots must not exceed the CPUs allocated to each Docker engine.

For a reusable list, `workers.lan.example.csv` provides the format:

```csv
Id,Address,Port,Slots
1,192.168.1.150,2222,1
2,192.168.1.151,2222,2
```

The file uses the exact header above and plain, unquoted fields. Each entry needs
an ID, a LAN IPv4 address or hostname, an SSH port, and between 1 and 64 slots.
Example addresses must be replaced, and unused rows removed.
Both Windows and Unix line endings are accepted:

```powershell
Copy-Item workers.lan.example.csv workers.csv
.\desktop.ps1 connect-all -WorkersFile .\workers.csv
.\desktop.ps1 status
.\desktop.ps1 validate
.\desktop.ps1 run
```

`connect-all` validates the whole file before opening new tunnels. A repeat run
keeps matching live connections and updates their slots. Adding a row adds a
worker; removing a row does not disconnect an existing worker. A changed
destination requires an explicit disconnect first. If a connection fails, earlier
successful connections remain available; `status` shows the registered workers.
An unreachable registered worker causes validation or execution to fail rather
than being silently excluded.

The Bash coordinator supports the same features:

```bash
bash ./desktop.sh master trust-code 'WORKER_2_PUBLIC_CODE' --verified 2
bash ./desktop.sh master connect 192.168.1.151 2222 2 2
bash ./desktop.sh master connect-all workers.csv
bash ./desktop.sh master validate
bash ./desktop.sh master run 22 4000000 1
```

The `connect` arguments are address, port, ID, and slots. The `run` arguments are
bits, key, master slots, and an optional uniform worker-slot override.
All remote MPI processes are launched by the coordinator, avoiding worker-to-worker
SSH trust. Their MPI data still travels between workers through the coordinator.
IP forwarding applies only inside the master container. No extra host firewall
ports are needed. A worker belongs to one coordinator at a time.

The address plan permits up to 254 workers, not unlimited performance. Coordinator
bandwidth, Docker CPU and memory allocations, and SSH overhead set practical
limits. Validation checks every worker pair, so its network checks grow with the
square of the worker count.

The worker does not run `mpirun`. It remains running while the Windows master
starts jobs.

## 5. Reconnection and shutdown

A worker restart or network interruption requires reconnecting that worker:

```powershell
.\desktop.ps1 disconnect -WorkerId 2
.\desktop.ps1 connect -WorkerId 2 -PeerAddress 192.168.1.151 -WorkerSlots 2
```

`disconnect` without an ID closes all worker tunnels. The Bash equivalent for one
worker is `bash ./desktop.sh master disconnect 2`. Disconnecting one worker leaves
the other tunnels usable. Restarting the coordinator clears its connection list;
`connect-all` rebuilds it from the CSV. Disconnect does not revoke trusted keys.
Reusing an ID for a different computer requires a separate identity review; the
launcher rejects changed host keys.

Shutdown on Windows:

```powershell
.\desktop.ps1 down
```

Shutdown on Mac:

```bash
bash ./desktop.sh worker down
```

The node identities survive shutdown in Docker volumes. `up` on the Mac should
always include its current LAN IP; the safe default publishes only on localhost.
The default SSH port is `2222`. A different port must be supplied to both the
worker's `up` command and the master's `connect` command.

## Validation limits

The automated test runs one master and two workers on three separate Docker
networks, with localhost-only published SSH ports. It covers legacy single-worker
commands, CSV validation, repeat and overlapping connections, worker-to-worker ping, MPI ring
messages and collective communication, per-worker slots, key recovery, exhaustive
coverage, independent disconnects, worker restart, and ID and slot limits:

```powershell
.\tests\desktop-smoke.ps1
```

Launcher argument checks do not start Docker containers:

```powershell
.\tests\desktop-launcher.ps1
```

```bash
bash ./tests/desktop-launcher.sh ./desktop.sh
```

The smoke test uses a separate Compose project and identities, so its simulated
workers do not become trusted by the real coordinator. It removes its containers
after the test and retains its test identity volumes.

This verifies the tunnel design on the current Windows Docker engine, not
the classmate's Mac, its emulation settings, or the physical Wi-Fi network.
The cross-computer `validate` command remains the acceptance test.
Mac emulation and TCP-over-SSH add overhead, so these measurements must not
be presented as native cross-computer MPI performance benchmarks.
