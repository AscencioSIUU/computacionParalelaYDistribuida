param(
    [ValidateSet('build', 'up', 'trust', 'validate', 'run', 'ips', 'shell', 'down')]
    [string]$Command = 'validate',
    [int]$Bits = 22,
    [UInt64]$Key = 4000000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Docker {
    & docker @args
    if ($LASTEXITCODE -ne 0) {
        throw "Docker fallo con codigo $LASTEXITCODE."
    }
}

function Set-ClusterTrust {
    $nodes = @('maestro', 'worker1', 'worker2')
    foreach ($peer in $nodes) {
        $clientKey = Invoke-Docker exec "mpi_$peer" cat /root/.ssh/id_ed25519.pub
        $hostKey = Invoke-Docker exec "mpi_$peer" cat /root/.ssh/host_ed25519_key.pub
        foreach ($node in $nodes) {
            Invoke-Docker exec "mpi_$node" mpi-trust $peer "$clientKey" "$hostKey"
        }
    }
}

function Copy-Hostfile {
    Invoke-Docker cp cluster_hosts mpi_maestro:/cluster/cluster_hosts
    Invoke-Docker exec mpi_maestro sed -i 's/\r$//' /cluster/cluster_hosts
}

Push-Location $PSScriptRoot
try {
    switch ($Command) {
        'build' { Invoke-Docker build -t mpi-cluster-image . }
        'up' {
            Invoke-Docker compose up -d --build --wait --wait-timeout 60
            Set-ClusterTrust
        }
        'trust' { Set-ClusterTrust }
        'validate' {
            Invoke-Docker exec mpi_maestro mpicc --version
            foreach ($peer in @('worker1', 'worker2')) {
                Invoke-Docker exec mpi_maestro ssh $peer hostname
            }
            Copy-Hostfile
            Invoke-Docker exec mpi_maestro timeout 30s mpirun `
                --hostfile /cluster/cluster_hosts `
                --mca btl_tcp_if_include 10.42.0.0/24 `
                --mca oob_tcp_if_include 10.42.0.0/24 -np 6 hostname
            $coverage = Invoke-Docker exec mpi_maestro timeout 30s mpi-run `
                /cluster/cluster_hosts 10.42.0.0/24 3 10 999999
            $coverage
            if (($coverage -join "`n") -notmatch 'Candidatas probadas: 1024') {
                throw 'La prueba exhaustiva no recorrio 1024 candidatas.'
            }
            $recovery = Invoke-Docker exec mpi_maestro timeout 30s mpi-run `
                /cluster/cluster_hosts 10.42.0.0/24 6 16 12345
            $recovery
            if (($recovery -join "`n") -notmatch 'Clave encontrada: 12345') {
                throw 'La prueba distribuida no recupero la clave 12345.'
            }
        }
        'run' {
            Copy-Hostfile
            $slots = 0
            foreach ($line in Get-Content -LiteralPath cluster_hosts) {
                $entry = ($line -split '#', 2)[0]
                foreach ($slot in [regex]::Matches($entry, '\bslots=(\d+)\b')) {
                    $slots += [int]$slot.Groups[1].Value
                }
            }
            Invoke-Docker exec mpi_maestro mpi-run /cluster/cluster_hosts `
                10.42.0.0/24 $slots $Bits $Key
        }
        'ips' {
            foreach ($node in @('mpi_maestro', 'mpi_worker1', 'mpi_worker2')) {
                Write-Output "${node}:"
                Invoke-Docker exec $node hostname -I
            }
        }
        'shell' { Invoke-Docker exec -it mpi_maestro bash }
        'down' { Invoke-Docker compose down }
    }
}
finally {
    Pop-Location
}
