# Windows master and Apple Silicon Mac worker

This two-computer setup uses Docker Desktop with Linux containers on both
computers. No separate Linux VM, host networking, VPN account, or router port
forwarding is required.

Both containers use `linux/amd64`. The Mac runs that image under emulation.
The master opens an encrypted SSH tunnel to the worker. MPI communicates over
the private tunnel addresses `10.77.0.1` and `10.77.0.2`, not the Docker bridge
addresses or the computers' Wi-Fi addresses.

## Requirements

- Both computers run the same project files and Docker Desktop with Linux
  containers. Apple Silicon must support amd64 emulation in Docker Desktop.
- The network permits direct TCP connections between participants. Being on
  the same Wi-Fi does not bypass guest-network or campus-network isolation.
- The Docker engine permits `/dev/net/tun` and the container-only `NET_ADMIN`
  capability. Docker policies or Enhanced Container Isolation can block this
  configuration. Changes to an organization's security policy require its approval.
- The private range `10.77.0.0/30` must not overlap a required network or VPN.
- Only the Mac worker publishes a port: TCP `2222`, bound to its chosen LAN IP.
  The Windows master publishes no ports and needs no new inbound firewall rule.

The tunnel permissions apply inside the containers, not to Windows or macOS.
`--privileged` is not used. The Mac firewall must allow the Docker worker's
incoming connection, preferably restricted to the master's LAN IP. The firewall
must remain enabled. No inbound MPI port ranges are needed for this setup.

## 1. Windows coordinator

From the project directory in PowerShell 7:

```powershell
.\desktop.ps1 up
.\desktop.ps1 identity
```

The identity command writes `.mpi-desktop/master.pub`. It contains two public
keys, not private credentials, and prints their fingerprints.
The master is ready for key exchange, but the tunnel is not connected yet.

## 2. Mac worker

The Mac needs the updated project files. If a `worker-setup.zip` bundle is
provided, it must be extracted to its own directory first. Commands run from
the extracted directory, which contains `Dockerfile` and `desktop.sh`.

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
healthy before continuing. `.mpi-desktop/worker.pub` contains its two public keys.
The printed fingerprints identify those keys.

If the Mac reports an unavailable tunnel device or `Operation not permitted`,
the engine cannot run this setup as configured. That error must be resolved
before a distributed test; successful local MPI alone is not sufficient.

## 3. Public-key exchange and verification

The master receives `worker.pub`. The worker receives `master.pub`, which is
already included at the root of the generated worker bundle.
Only these public files are exchanged. Private keys remain in per-node Docker
volumes and must never be copied or sent.

The received fingerprints can be inspected before trust is granted:

Windows:

```powershell
.\desktop.ps1 inspect -PeerFile .\worker.pub
```

Mac:

```bash
bash ./desktop.sh worker inspect ./master.pub
```

Both fingerprints must match the owner's `identity` output through an
independent check, such as direct comparison with the owner's screen.
After that verification:

Windows:

```powershell
.\desktop.ps1 trust -PeerFile .\worker.pub -Verified
```

Mac:

```bash
bash ./desktop.sh worker trust ./master.pub --verified
```

The tool rejects a changed server identity instead of silently accepting it.
Trust grants the classmate remote access as root inside the project container;
only the intended classmate's verified keys belong here.

## 4. Connection and test from Windows

The master's command uses the Mac's real LAN IPv4 address:

```powershell
.\desktop.ps1 connect -PeerAddress 10.15.36.20
.\desktop.ps1 status
.\desktop.ps1 validate
.\desktop.ps1 run -Bits 22 -Key 4000000
```

Expected validation results:

- Ping succeeds through `tun0`.
- SSH returns `mpi-worker`.
- Both nodes report the `amd64` package architecture.
- Process placement prints `mpi-master` and `mpi-worker`.
- The short search recovers key `50000`.
- The exhaustive search tests exactly `1024` candidates.

`run` defaults to one MPI process per computer. More processes can be selected
without exceeding the CPU allocated to each Docker engine:

```powershell
.\desktop.ps1 run -MasterSlots 2 -WorkerSlots 1
```

The worker does not run `mpirun`. It remains running while the Windows master
starts jobs.

## 5. Reconnection and shutdown

A worker restart or network interruption requires reconnecting the tunnel:

```powershell
.\desktop.ps1 disconnect
.\desktop.ps1 connect -PeerAddress 10.15.36.20
```

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

The automated test runs two amd64 containers on separate Docker networks,
connects through a localhost-only published SSH port, verifies MPI through
the encrypted tunnel, and checks reconnection:

```powershell
.\tests\desktop-smoke.ps1
```

It uses a separate Compose project and identities, so its simulated worker
does not become trusted by the real coordinator. It removes its containers
after the test and retains its test identity volumes.

This verifies the tunnel design on the current Windows Docker engine, not
the classmate's Mac, its emulation settings, or the physical Wi-Fi network.
The cross-computer `validate` command remains the acceptance test.
Mac emulation and TCP-over-SSH add overhead, so these measurements must not
be presented as native cross-computer MPI performance benchmarks.
