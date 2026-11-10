param(
    [ValidateSet('up', 'identity', 'inspect', 'trust', 'connect', 'connect-all', 'disconnect', 'status', 'validate', 'run', 'down')]
    [string]$Command = 'status',
    [ValidateSet('master', 'worker')]
    [string]$Role = 'master',
    [string]$BindAddress = '127.0.0.1',
    [string]$PeerAddress,
    [string]$PeerFile,
    [string]$PeerCode,
    [ValidateRange(1, 65535)]
    [int]$Port = 2222,
    [ValidateRange(1, 40)]
    [int]$Bits = 22,
    [UInt64]$Key = 4000000,
    [ValidateRange(1, 64)]
    [int]$MasterSlots = 1,
    [ValidateRange(1, 64)]
    [int]$WorkerSlots = 1,
    [switch]$Verified,
    [ValidateRange(1, 254)]
    [int]$WorkerId = 1,
    [string]$WorkersFile
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
            Invoke-Node fingerprints
            $code = Invoke-Node identity-code
            Write-Output "Codigo publico: $code"
        }
        { $_ -in 'inspect', 'trust' } {
            if ([bool]$PeerFile -eq [bool]$PeerCode) {
                throw 'Se requiere exactamente uno de PeerCode o PeerFile.'
            }
            if ($Command -eq 'trust' -and -not $Verified) {
                throw 'Las dos huellas deben verificarse con el propietario antes de usar -Verified.'
            }
            if ($PeerCode) {
                Invoke-Node "$Command-code" $PeerCode $WorkerId
            }
            else {
                Invoke-Compose cp $PeerFile "${Role}:/tmp/mpi-peer.pub"
                Invoke-Node fingerprints /tmp/mpi-peer.pub
                if ($Command -eq 'trust') { Invoke-Node trust /tmp/mpi-peer.pub $WorkerId }
            }
        }
        'connect' {
            if (-not $PeerAddress) { throw 'PeerAddress debe indicar la IP LAN del worker.' }
            Invoke-Node connect $PeerAddress $Port $WorkerId $WorkerSlots
        }
        'connect-all' {
            if (-not $WorkersFile) { throw 'WorkersFile debe indicar un CSV con Id,Address,Port,Slots.' }
            $remote = "/tmp/mpi-workers-$([guid]::NewGuid().ToString('N')).csv"
            Invoke-Compose cp $WorkersFile "${Role}:$remote"
            try {
                Invoke-Node connect-all $remote
            }
            finally {
                Invoke-Compose exec -T $Role rm -f $remote
            }
        }
        'disconnect' {
            if ($PSBoundParameters.ContainsKey('WorkerId')) { Invoke-Node disconnect $WorkerId }
            else { Invoke-Node disconnect }
        }
        'run' {
            $arguments = @('run', $Bits, $Key, $MasterSlots)
            if ($PSBoundParameters.ContainsKey('WorkerSlots')) { $arguments += $WorkerSlots }
            Invoke-Node @arguments
        }
        'down' { Invoke-Compose down }
        default { Invoke-Node $Command }
    }
}
finally {
    $env:MPI_BIND_IP = $previousBind
    $env:MPI_SSH_PORT = $previousPort
    Pop-Location
}
