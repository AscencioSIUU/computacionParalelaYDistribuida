$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Compose {
    & docker compose -p cc3069-desktop-smoke -f docker-compose.desktop.yml -f tests/docker-compose.desktop-smoke.yml `
        --profile master --profile worker @args
    if ($LASTEXITCODE -ne 0) { throw "Docker fallo con codigo $LASTEXITCODE." }
}

function Assert-Rejected {
    & docker compose -p cc3069-desktop-smoke -f docker-compose.desktop.yml -f tests/docker-compose.desktop-smoke.yml `
        --profile master --profile worker exec -T master timeout 15s mpi-desktop @args
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 124) {
        throw "El comando no fue rechazado correctamente: $args"
    }
}

$previousBind = $env:MPI_BIND_IP
$previousPort = $env:MPI_SSH_PORT
$workersFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".mpi-desktop\desktop-smoke-$([guid]::NewGuid().ToString('N')).csv"
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $env:MPI_BIND_IP = '127.0.0.1'
    $env:MPI_SSH_PORT = '32222'
    & docker build --platform linux/amd64 -t mpi-cluster-desktop .
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo construir la imagen de prueba.' }
    Invoke-Compose up -d --no-build --wait --wait-timeout 90
    foreach ($peer in @('master', 'worker')) {
        $code = Invoke-Compose exec -T $peer mpi-desktop identity-code
        $target = if ($peer -eq 'master') { 'worker' } else { 'master' }
        Invoke-Compose exec -T $target mpi-desktop inspect-code "$code"
        Invoke-Compose exec -T $target mpi-desktop trust-code "$code"
    }
    Assert-Rejected trust-code not-base64
    Assert-Rejected connect host.docker.internal 32223 0
    Assert-Rejected connect host.docker.internal 32223 255
    Invoke-Compose exec -T master mpi-desktop connect host.docker.internal 32222
    Invoke-Compose exec -T master mpi-desktop status
    Invoke-Compose exec -T master mpi-desktop validate
    $result = Invoke-Compose exec -T master timeout 60s mpi-desktop run 22 4000000 1 1
    if (($result -join "`n") -notmatch 'Clave encontrada: 4000000') {
        throw 'La busqueda por el tunel no recupero la clave 4000000.'
    }
    Assert-Rejected connect host.docker.internal 32222
    Assert-Rejected connect host.docker.internal 32223 253
    $masterCode = Invoke-Compose exec -T master mpi-desktop identity-code
    $workerCode = Invoke-Compose exec -T worker2 mpi-desktop identity-code
    Invoke-Compose exec -T worker2 mpi-desktop trust-code "$masterCode"
    Invoke-Compose exec -T master mpi-desktop trust-code "$workerCode" 2
    Assert-Rejected trust-code "$workerCode" 1

    New-Item -ItemType Directory -Path (Split-Path $workersFile -Parent) -Force | Out-Null
    foreach ($invalid in @(
        "Id,Address,Port,Slots`n2,host.docker.internal,32223,1`n2,host.docker.internal,32222,1",
        "Id,Address,Port,Slots`n2,host.docker.internal,32223,1`n3,host.docker.internal,32223,1",
        "Id,Address,Port,Slots`n2,host.docker.internal,32223,1`n255,host.docker.internal,32224,1",
        "Id,Address,Port,Slots`n2,host.docker.internal,32223,0",
        "Id,Address,Port,Slots`n2,host.docker.internal,65536,1",
        "Id,Address,Port,Slots`n",
        "Name,Address,Port,Slots`n2,host.docker.internal,32223,1"
    )) {
        $invalid | Set-Content -LiteralPath $workersFile
        Invoke-Compose cp $workersFile master:/tmp/workers.csv
        Assert-Rejected connect-all /tmp/workers.csv
    }
    Invoke-Compose exec -T master test ! -f /run/mpi-desktop/workers/2
    "Id,Address,Port,Slots`r`n1,host.docker.internal,32222,1`r`n2,host.docker.internal,32223,2" |
        Set-Content -LiteralPath $workersFile -NoNewline
    Invoke-Compose cp $workersFile master:/tmp/workers.csv
    Invoke-Compose exec -T master timeout 30s mpi-desktop connect-all /tmp/workers.csv
    Invoke-Compose exec -T master timeout 15s mpi-desktop connect-all /tmp/workers.csv
    Invoke-Compose exec -T master timeout 20s bash -c `
        'mpi-desktop connect-all /tmp/workers.csv & first=$!; mpi-desktop connect-all /tmp/workers.csv & second=$!; failed=0; wait "$first" || failed=1; wait "$second" || failed=1; exit "$failed"'
    "Id,Address,Port,Slots`n1,host.docker.internal,32222,1`n2,host.docker.internal,32223,3" |
        Set-Content -LiteralPath $workersFile
    Invoke-Compose cp $workersFile master:/tmp/updated-workers.csv
    Invoke-Compose exec -T master mpi-desktop connect-all /tmp/updated-workers.csv
    $updated = Invoke-Compose exec -T master cat /run/mpi-desktop/workers/2
    if ("$updated" -ne 'host.docker.internal 32223 3') { throw 'Los slots de un worker conectado no se actualizaron.' }
    Invoke-Compose exec -T master mpi-desktop connect-all /tmp/workers.csv
    Invoke-Compose exec -T master mpi-desktop validate
    foreach ($node in @('master', 'worker', 'worker2')) {
        Invoke-Compose cp tests/mpi-mesh.c "${node}:/tmp/mpi-mesh.c"
        Invoke-Compose exec -T $node mpicc -std=c11 -Wall -Wextra -Werror /tmp/mpi-mesh.c -o /tmp/mpi-mesh
    }
    foreach ($slots in @(@{ Master = 1; Expected = 4 }, @{ Master = 2; Expected = 5 })) {
        $mesh = Invoke-Compose exec -T -e BRUTEFORCE=/tmp/mpi-mesh master timeout 45s mpi-desktop run 10 999999 $slots.Master
        $text = $mesh -join "`n"
        $mesh
        if ($text -notmatch "MPI mesh PASS: ranks=$($slots.Expected)" -or
            $text -notmatch 'on mpi-master' -or $text -notmatch 'on mpi-worker2' -or
            $text -notmatch 'on mpi-worker(?:\r?\n|$)') {
            throw 'La malla MPI no incluyo los tres nodos y sus slots configurados.'
        }
    }
    $override = Invoke-Compose exec -T -e BRUTEFORCE=/tmp/mpi-mesh master timeout 45s mpi-desktop run 10 999999 1 1
    if (($override -join "`n") -notmatch 'MPI mesh PASS: ranks=3') { throw 'La sobreescritura de slots fallo.' }
    Invoke-Compose exec -T master bash -n /usr/local/bin/mpi-desktop.sh
    Invoke-Compose cp desktop.sh master:/tmp/desktop.sh
    Invoke-Compose exec -T master bash -n /tmp/desktop.sh
    Invoke-Compose exec -T master mpi-desktop disconnect 1
    Invoke-Compose exec -T master mpi-desktop validate
    Invoke-Compose exec -T master mpi-desktop connect host.docker.internal 32222
    Invoke-Compose exec -T master mpi-desktop disconnect 2
    Invoke-Compose exec -T master mpi-desktop validate
    Invoke-Compose exec -T master mpi-desktop connect host.docker.internal 32223 2 2
    Invoke-Compose stop worker2
    Assert-Rejected validate
    Invoke-Compose up -d --no-build --wait --wait-timeout 90 worker2
    Invoke-Compose exec -T master timeout 30s mpi-desktop connect-all /tmp/workers.csv
    Invoke-Compose exec -T master mpi-desktop status
    Invoke-Compose exec -T master mpi-desktop disconnect 2
    Invoke-Compose exec -T master mpi-desktop trust-code "$workerCode" 254
    Invoke-Compose exec -T master mpi-desktop connect host.docker.internal 32223 254 64
    Invoke-Compose exec -T master mpi-desktop status
    $hostfile = Invoke-Compose exec -T master cat /run/mpi-desktop/hosts
    if (($hostfile -join "`n") -notmatch '10.77.254.2 slots=64 max_slots=64') {
        throw 'El limite de WorkerId o slots fallo.'
    }
    Invoke-Compose exec -T master mpi-desktop validate
    Invoke-Compose exec -T master mpi-desktop disconnect
    Assert-Rejected status
    Invoke-Compose exec -T master mpi-desktop disconnect
    Write-Output 'PASS: tres redes Docker, tuneles independientes, concurrencia, trafico entre workers, MPI, slots, cobertura, limites y reconexion.'
}
finally {
    Invoke-Compose down
    if (Test-Path -LiteralPath $workersFile) { Remove-Item -LiteralPath $workersFile }
    $env:MPI_BIND_IP = $previousBind
    $env:MPI_SSH_PORT = $previousPort
    Pop-Location
}
