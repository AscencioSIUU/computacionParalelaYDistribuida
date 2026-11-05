$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Compose {
    & docker compose -p cc3069-desktop-smoke -f docker-compose.desktop.yml `
        --profile master --profile worker @args
    if ($LASTEXITCODE -ne 0) { throw "Docker fallo con codigo $LASTEXITCODE." }
}

$previousBind = $env:MPI_BIND_IP
$previousPort = $env:MPI_SSH_PORT
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $env:MPI_BIND_IP = '127.0.0.1'
    $env:MPI_SSH_PORT = '32222'
    Invoke-Compose up -d --build --wait --wait-timeout 90
    foreach ($peer in @('master', 'worker')) {
        $keys = @(Invoke-Compose exec -T $peer mpi-desktop identity)
        if ($keys.Count -ne 2) { throw 'Se esperaban dos claves publicas.' }
        $target = if ($peer -eq 'master') { 'worker' } else { 'master' }
        $address = if ($peer -eq 'master') { '10.77.0.1' } else { '10.77.0.2' }
        Invoke-Compose exec -T $target mpi-trust "mpi-$peer" "$($keys[0])" "$($keys[1])"
        Invoke-Compose exec -T $target mpi-trust $address "$($keys[0])" "$($keys[1])"
    }
    Invoke-Compose exec -T master mpi-desktop connect host.docker.internal 32222
    Invoke-Compose exec -T master mpi-desktop status
    Invoke-Compose exec -T master mpi-desktop validate
    $result = Invoke-Compose exec -T master timeout 60s mpi-desktop run 22 4000000 1 1
    if (($result -join "`n") -notmatch 'Clave encontrada: 4000000') {
        throw 'La busqueda por el tunel no recupero la clave 4000000.'
    }
    Invoke-Compose exec -T master bash -n /usr/local/bin/mpi-desktop.sh
    Invoke-Compose cp desktop.sh master:/tmp/desktop.sh
    Invoke-Compose exec -T master bash -n /tmp/desktop.sh
    Invoke-Compose exec -T master mpi-desktop disconnect
    Invoke-Compose exec -T master mpi-desktop connect host.docker.internal 32222
    Invoke-Compose exec -T master mpi-desktop status
    Write-Output 'PASS: redes Docker separadas, tunel SSH, MPI amd64, cobertura y reconexion.'
}
finally {
    Invoke-Compose down
    $env:MPI_BIND_IP = $previousBind
    $env:MPI_SSH_PORT = $previousPort
    Pop-Location
}
