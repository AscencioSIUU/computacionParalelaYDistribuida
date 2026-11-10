$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$launcher = Join-Path (Split-Path $PSScriptRoot -Parent) 'desktop.ps1'
$global:DesktopTestCalls = [System.Collections.Generic.List[object]]::new()
$previousBind = $env:MPI_BIND_IP
$previousPort = $env:MPI_SSH_PORT

function docker {
    $global:DesktopTestCalls.Add(@($args))
    $global:LASTEXITCODE = 0
}

function Assert-Tail {
    param([string]$Expected)
    $actual = $global:DesktopTestCalls[-1] -join ' '
    if (-not $actual.EndsWith($Expected)) { throw "Expected '$Expected', received '$actual'." }
}

try {
    $env:MPI_BIND_IP = 'original-bind'
    $env:MPI_SSH_PORT = 'original-port'
    & $launcher connect -PeerAddress 192.168.1.150
    Assert-Tail 'exec -T master mpi-desktop connect 192.168.1.150 2222 1 1'
    & $launcher connect -PeerAddress 192.168.1.151 -Port 2233 -WorkerId 2 -WorkerSlots 3
    Assert-Tail 'exec -T master mpi-desktop connect 192.168.1.151 2233 2 3'
    & $launcher trust -PeerCode public-code -WorkerId 2 -Verified
    Assert-Tail 'exec -T master mpi-desktop trust-code public-code 2'
    & $launcher trust -PeerFile peer.public -WorkerId 3 -Verified
    Assert-Tail 'exec -T master mpi-desktop trust /tmp/mpi-peer.pub 3'
    & $launcher inspect -Role worker -PeerCode master-code
    Assert-Tail 'exec -T worker mpi-desktop inspect-code master-code 1'
    & $launcher run
    Assert-Tail 'exec -T master mpi-desktop run 22 4000000 1'
    & $launcher run -Bits 16 -Key 50000 -MasterSlots 2 -WorkerSlots 3
    Assert-Tail 'exec -T master mpi-desktop run 16 50000 2 3'
    & $launcher disconnect
    Assert-Tail 'exec -T master mpi-desktop disconnect'
    & $launcher disconnect -WorkerId 2
    Assert-Tail 'exec -T master mpi-desktop disconnect 2'
    $start = $global:DesktopTestCalls.Count
    & $launcher connect-all -WorkersFile workers.csv
    $calls = $global:DesktopTestCalls
    if ($calls.Count -ne $start + 3) { throw 'connect-all must copy, connect and clean up its temporary file.' }
    $remote = "$($calls[$start][-1])" -replace '^master:', ''
    if ($remote -notmatch '^/tmp/mpi-workers-[0-9a-f]{32}\.csv$') { throw 'The CSV path is not unique.' }
    if (-not (($calls[$start + 1] -join ' ').EndsWith("mpi-desktop connect-all $remote"))) {
        throw 'connect-all did not receive the copied CSV.'
    }
    Assert-Tail "exec -T master rm -f $remote"
    & $launcher connect-all -WorkersFile workers.csv
    if ($remote -eq ("$($calls[-3][-1])" -replace '^master:', '')) { throw 'Repeated CSV copies share a path.' }
    foreach ($action in @(
        { & $launcher trust -PeerCode public-code },
        { & $launcher connect },
        { & $launcher connect -PeerAddress 192.168.1.150 -WorkerId 0 },
        { & $launcher connect -PeerAddress 192.168.1.150 -WorkerId 255 },
        { & $launcher connect-all }
    )) {
        $before = $calls.Count
        $failed = $false
        try { & $action }
        catch { $failed = $true }
        if (-not $failed -or $calls.Count -ne $before) { throw 'An invalid launcher request reached Docker.' }
    }
    if ($env:MPI_BIND_IP -ne 'original-bind' -or $env:MPI_SSH_PORT -ne 'original-port') {
        throw 'The launcher changed the caller environment.'
    }
    Write-Output 'PASS: PowerShell multi-worker arguments, legacy defaults, CSV isolation and validation.'
}
finally {
    $env:MPI_BIND_IP = $previousBind
    $env:MPI_SSH_PORT = $previousPort
    Remove-Variable DesktopTestCalls -Scope Global
}
