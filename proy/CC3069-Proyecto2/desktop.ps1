param(
    [ValidateSet('up', 'identity', 'inspect', 'trust', 'connect', 'disconnect', 'status', 'validate', 'run', 'down')]
    [string]$Command = 'status',
    [ValidateSet('master', 'worker')]
    [string]$Role = 'master',
    [string]$BindAddress = '127.0.0.1',
    [string]$PeerAddress,
    [string]$PeerFile,
    [ValidateRange(1, 65535)]
    [int]$Port = 2222,
    [ValidateRange(1, 40)]
    [int]$Bits = 22,
    [UInt64]$Key = 4000000,
    [ValidateRange(1, 64)]
    [int]$MasterSlots = 1,
    [ValidateRange(1, 64)]
    [int]$WorkerSlots = 1,
    [switch]$Verified
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Compose {
    & docker compose -p cc3069-desktop -f docker-compose.desktop.yml --profile $Role @args
    if ($LASTEXITCODE -ne 0) { throw "Docker fallo con codigo $LASTEXITCODE." }
}

function Invoke-Node {
    Invoke-Compose exec -T $Role mpi-desktop @args
}

$previousBind = $env:MPI_BIND_IP
$previousPort = $env:MPI_SSH_PORT
Push-Location $PSScriptRoot
try {
    $env:MPI_BIND_IP = $BindAddress
    $env:MPI_SSH_PORT = "$Port"
    switch ($Command) {
        'up' {
            if (-not [System.Net.IPAddress]::TryParse($BindAddress, [ref]([System.Net.IPAddress]$null))) {
                throw 'BindAddress debe ser una direccion IP.'
            }
            Invoke-Compose up -d --build --wait --wait-timeout 90 $Role
        }
        'identity' {
            $identity = @(Invoke-Node identity)
            if ($identity.Count -ne 2) { throw 'Se esperaban dos claves publicas.' }
            [void][System.IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot '.mpi-desktop'))
            $path = Join-Path $PSScriptRoot ".mpi-desktop/$Role.pub"
            [System.IO.File]::WriteAllLines($path, [string[]]$identity, [System.Text.UTF8Encoding]::new($false))
            Invoke-Node fingerprints
            Write-Output "Claves publicas: $path"
        }
        { $_ -in 'inspect', 'trust' } {
            if (-not $PeerFile) { throw 'PeerFile debe indicar el archivo publico del otro nodo.' }
            if ($Command -eq 'trust' -and -not $Verified) {
                throw 'Las dos huellas deben verificarse con el propietario antes de usar -Verified.'
            }
            Invoke-Compose cp $PeerFile "${Role}:/tmp/mpi-peer.pub"
            Invoke-Node fingerprints /tmp/mpi-peer.pub
            if ($Command -eq 'trust') { Invoke-Node trust /tmp/mpi-peer.pub }
        }
        'connect' {
            if (-not $PeerAddress) { throw 'PeerAddress debe indicar la IP LAN del Mac.' }
            Invoke-Node connect $PeerAddress $Port
        }
        'run' { Invoke-Node run $Bits $Key $MasterSlots $WorkerSlots }
        'down' { Invoke-Compose down }
        default { Invoke-Node $Command }
    }
}
finally {
    $env:MPI_BIND_IP = $previousBind
    $env:MPI_SSH_PORT = $previousPort
    Pop-Location
}
