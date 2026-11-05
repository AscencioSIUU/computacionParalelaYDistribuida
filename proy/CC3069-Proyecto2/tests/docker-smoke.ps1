param([switch]$KeepRunning)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Docker {
    & docker @args
    if ($LASTEXITCODE -ne 0) {
        throw "Docker fallo con codigo $LASTEXITCODE."
    }
}

function Assert-Rejected {
    & docker @args
    if ($LASTEXITCODE -eq 0) {
        throw 'La operacion debio ser rechazada.'
    }
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & ./cluster.ps1 up
    Invoke-Docker run --rm --entrypoint bash mpi-cluster-image -c `
        'test ! -e /root/.ssh/id_ed25519 && test ! -e /root/.ssh/host_ed25519_key && test -z "$(find /etc/ssh -name "ssh_host_*" -print -quit)"'

    $identities = @{}
    foreach ($node in @('mpi_maestro', 'mpi_worker1', 'mpi_worker2')) {
        $identities[$node] = @(
            Invoke-Docker exec $node cat /root/.ssh/id_ed25519.pub
            Invoke-Docker exec $node cat /root/.ssh/host_ed25519_key.pub
        )
    }
    if (@($identities.Values | ForEach-Object { $_[0] } | Sort-Object -Unique).Count -ne 3) {
        throw 'Los nodos comparten la identidad del cliente.'
    }
    if (@($identities.Values | ForEach-Object { $_[1] } | Sort-Object -Unique).Count -ne 3) {
        throw 'Los nodos comparten la identidad del servidor.'
    }

    $clientKey = $identities['mpi_worker1'][0]
    $hostKey = $identities['mpi_worker1'][1]
    $wrongHostKey = $identities['mpi_maestro'][1]
    Assert-Rejected exec mpi_maestro mpi-trust worker1 "$clientKey" "$wrongHostKey"
    Assert-Rejected exec mpi_maestro mpi-trust worker1 "$clientKey`n$clientKey" "$hostKey"
    Assert-Rejected exec mpi_maestro ssh -o HostKeyAlias=unregistered-node worker1 true
    & ./cluster.ps1 trust

    Invoke-Docker exec mpi_maestro bash -c `
        'printf "maestro slots=2\r\nworker1 slots=2\r\nworker2 slots=2\r\n" > /tmp/mpi-crlf-hosts'
    $recovery = Invoke-Docker exec mpi_maestro timeout 30s mpi-run `
        /tmp/mpi-crlf-hosts 10.42.0.0/24 6 16 12345
    if (($recovery -join "`n") -notmatch 'Clave encontrada: 12345') {
        throw 'El hostfile CRLF no funciono.'
    }

    Invoke-Docker compose up -d --no-build --force-recreate --wait --wait-timeout 60
    foreach ($node in $identities.Keys) {
        $clientAfter = Invoke-Docker exec $node cat /root/.ssh/id_ed25519.pub
        $hostAfter = Invoke-Docker exec $node cat /root/.ssh/host_ed25519_key.pub
        if ($clientAfter -ne $identities[$node][0] -or $hostAfter -ne $identities[$node][1]) {
            throw "Las claves de $node cambiaron al recrear el contenedor."
        }
    }

    Invoke-Docker cp cluster.sh mpi_maestro:/tmp/cluster.sh
    foreach ($script in @('/tmp/cluster.sh', '/usr/local/bin/entrypoint.sh',
            '/usr/local/bin/mpi-trust.sh', '/usr/local/bin/mpi-run.sh')) {
        Invoke-Docker exec mpi_maestro bash -n $script
    }
    Invoke-Docker compose -f docker-compose.lan.yml config --quiet
    & ./cluster.ps1 validate
    $fullRun = & ./cluster.ps1 run -Bits 22 -Key 4000000
    if (($fullRun -join "`n") -notmatch 'Clave encontrada: 4000000') {
        throw 'La busqueda distribuida no recupero la clave 4000000.'
    }
    Write-Output 'PASS: imagen sin claves, identidades independientes, confianza SSH, CRLF, persistencia y MPI.'
}
finally {
    if (-not $KeepRunning) {
        & ./cluster.ps1 down
    }
    Pop-Location
}
