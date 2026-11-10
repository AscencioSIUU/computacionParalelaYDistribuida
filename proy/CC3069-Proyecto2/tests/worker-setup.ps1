$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path $root ".mpi-desktop\worker-test-$([guid]::NewGuid().ToString('N'))"
$hadState = Test-Path variable:global:WorkerTestState
$previousState = if ($hadState) { $global:WorkerTestState } else { $null }

function Reset-TestState {
    $global:WorkerTestState = @{
        Addresses = @([pscustomobject]@{
            IPAddress = '192.168.1.150'; InterfaceIndex = 21; AddressState = 'Preferred'
        })
        Engine = 'linux'; Endpoint = 'npipe:////./pipe/dockerDesktopLinuxEngine'
        Rule = $null; Creates = 0; Updates = 0; Starts = 0; Ups = @()
        Running = $true; Health = 'healthy'; Published = '192.168.1.150:2222'
        Reachable = $true; Denied = $false; StartFailure = $false; UpFailure = $false
    }
}

function Get-NetIPConfiguration {
    [pscustomobject]@{ IPv4DefaultGateway = '192.168.1.1'; IPv4Address = $global:WorkerTestState.Addresses }
}

function Get-NetAdapter {
    param($InterfaceIndex)
    [pscustomobject]@{ Name = 'Wi-Fi' }
}

function Get-NetConnectionProfile {
    param($InterfaceIndex, $ErrorAction)
    [pscustomobject]@{ NetworkCategory = 'Public' }
}

function Get-NetFirewallRule {
    param($Name, $ErrorAction)
    $global:WorkerTestState.Rule
}

function New-NetFirewallRule {
    param($Name, $Enabled, $Direction, $Action, $Profile, $InterfaceAlias,
        $Protocol, $LocalPort, $LocalAddress, $RemoteAddress, $RemotePort, $EdgeTraversalPolicy, $ErrorAction)
    Assert-True ($ErrorAction -eq 'Stop') 'Firewall mutations must stop on errors.'
    if ($global:WorkerTestState.Denied) { throw 'Access denied' }
    $global:WorkerTestState.Creates++
    $global:WorkerTestState.Rule = [pscustomobject]([hashtable]$PSBoundParameters)
}

function Set-NetFirewallRule {
    param($Name, $Enabled, $Direction, $Action, $Profile, $InterfaceAlias,
        $Protocol, $LocalPort, $LocalAddress, $RemoteAddress, $RemotePort, $EdgeTraversalPolicy, $ErrorAction)
    Assert-True ($ErrorAction -eq 'Stop') 'Firewall mutations must stop on errors.'
    if ($global:WorkerTestState.Denied) { throw 'Access denied' }
    $global:WorkerTestState.Updates++
    $global:WorkerTestState.Rule = [pscustomobject]([hashtable]$PSBoundParameters)
}

function Get-NetFirewallPortFilter {
    process { $global:WorkerTestState.Rule }
}

function Get-NetFirewallAddressFilter {
    process { $global:WorkerTestState.Rule }
}

function Get-NetFirewallInterfaceFilter {
    process { $global:WorkerTestState.Rule }
}

function Test-NetConnection {
    param($ComputerName, $Port, $InformationLevel, $WarningAction)
    $global:WorkerTestState.Reachable
}

function docker {
    $global:LASTEXITCODE = 0
    switch ($args[0]) {
        'context' { $global:WorkerTestState.Endpoint }
        'info' {
            if ($global:WorkerTestState.Engine) { $global:WorkerTestState.Engine }
            else { $global:LASTEXITCODE = 1 }
        }
        'desktop' {
            $global:WorkerTestState.Starts++
            if ($global:WorkerTestState.StartFailure) { $global:LASTEXITCODE = 1 }
            else { $global:WorkerTestState.Engine = 'linux' }
        }
        'ps' { if ($global:WorkerTestState.Running) { 'test-worker' } }
        'inspect' { $global:WorkerTestState.Health }
        'port' { $global:WorkerTestState.Published }
        default { throw "Unexpected Docker command: $args" }
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Setup {
    & "$fixture\worker.ps1" @args | Out-Null
}

function Assert-Fails {
    param([scriptblock]$Action, [string]$Pattern)
    $failed = $false
    try { & $Action }
    catch {
        $failed = $true
        if ($_.Exception.Message -notmatch $Pattern) { throw }
    }
    Assert-True $failed "Expected failure: $Pattern"
}

try {
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    Copy-Item -LiteralPath "$root\worker.ps1" -Destination "$fixture\worker.ps1"
    @'
param($Command, $Role, $BindAddress, $Port)
if ($global:WorkerTestState.UpFailure) { throw 'Compose failed' }
$global:WorkerTestState.Ups += [pscustomobject]@{
    Command = $Command; Role = $Role; BindAddress = $BindAddress; Port = $Port
}
'@ | Set-Content -LiteralPath "$fixture\desktop.ps1"

    Reset-TestState
    Invoke-Setup -WhatIf
    Assert-True ($global:WorkerTestState.Creates -eq 0 -and $global:WorkerTestState.Ups.Count -eq 0) 'WhatIf changed the machine.'

    Reset-TestState
    $global:WorkerTestState.Addresses += [pscustomobject]@{
        IPAddress = '10.1.1.2'; InterfaceIndex = 22; AddressState = 'Preferred'
    }
    Assert-Fails { Invoke-Setup } 'unica IPv4'
    Invoke-Setup -BindAddress '192.168.1.150' -WhatIf
    Assert-Fails { Invoke-Setup -BindAddress '0.0.0.0' } 'unica IPv4'

    Reset-TestState
    $global:WorkerTestState.Endpoint = 'ssh://remote-engine'
    Assert-Fails { Invoke-Setup } 'motor remoto'
    Assert-True ($global:WorkerTestState.Creates -eq 0) 'Remote Docker changed the firewall.'

    Reset-TestState
    $global:WorkerTestState.Denied = $true
    Assert-Fails { Invoke-Setup } 'administrador'
    Assert-True ($global:WorkerTestState.Ups.Count -eq 0) 'Worker started without firewall access.'

    Reset-TestState
    Invoke-Setup
    $state = $global:WorkerTestState
    Assert-True ($state.Creates -eq 1 -and $state.Updates -eq 0 -and $state.Starts -eq 0) 'Incorrect first setup.'
    Assert-True ($state.Ups.Count -eq 1 -and $state.Ups[0].Command -eq 'up' -and
        $state.Ups[0].Role -eq 'worker' -and $state.Ups[0].BindAddress -eq '192.168.1.150' -and
        $state.Ups[0].Port -eq 2222) 'Wrong role, bind address or port.'
    Assert-True ($state.Rule.Name -eq 'CC3069-MPI-Worker-2222' -and
        $state.Rule.RemoteAddress -eq 'LocalSubnet' -and $state.Rule.LocalAddress -eq '192.168.1.150' -and
        $state.Rule.Protocol -eq 'TCP' -and $state.Rule.LocalPort -eq 2222 -and
        $state.Rule.InterfaceAlias -eq 'Wi-Fi' -and $state.Rule.EdgeTraversalPolicy -eq 'Block' -and
        $state.Rule.Profile -eq 'Any' -and $state.Rule.Action -eq 'Allow' -and
        $state.Rule.Direction -eq 'Inbound') 'Firewall is not scoped to LAN SSH.'
    Invoke-Setup
    Assert-True ($state.Creates -eq 1 -and $state.Updates -eq 1 -and $state.Ups.Count -eq 2) 'Repeated setup duplicated the rule.'
    Invoke-Setup -CheckOnly
    Assert-True ($state.Creates -eq 1 -and $state.Updates -eq 1 -and $state.Ups.Count -eq 2) 'CheckOnly changed the machine.'
    $state.Denied = $true
    Assert-Fails { Invoke-Setup } 'administrador'
    Assert-True ($state.Ups.Count -eq 2) 'Worker restarted after a firewall update was denied.'
    $state.Denied = $false
    $state.Addresses[0].IPAddress = '192.168.1.151'
    $state.Published = '192.168.1.151:2222'
    Invoke-Setup
    Assert-True ($state.Rule.LocalAddress -eq '192.168.1.151' -and $state.Updates -eq 2) 'Changed LAN address was not applied.'

    Reset-TestState
    $global:WorkerTestState.Engine = ''
    $global:WorkerTestState.Published = '192.168.1.150:2233'
    Invoke-Setup -Port 2233
    Assert-True ($global:WorkerTestState.Starts -eq 1 -and
        $global:WorkerTestState.Rule.LocalPort -eq 2233 -and
        $global:WorkerTestState.Rule.Name -eq 'CC3069-MPI-Worker-2233' -and
        $global:WorkerTestState.Ups[0].Port -eq 2233) 'Docker startup or custom port failed.'

    Reset-TestState
    $global:WorkerTestState.Engine = ''
    $global:WorkerTestState.StartFailure = $true
    Assert-Fails { Invoke-Setup } 'no pudo iniciar'
    Assert-True ($global:WorkerTestState.Ups.Count -eq 0) 'Worker started after Docker startup failed.'

    Reset-TestState
    $global:WorkerTestState.Engine = 'windows'
    Assert-Fails { Invoke-Setup } 'Linux containers'
    Assert-True ($global:WorkerTestState.Ups.Count -eq 0) 'Windows containers were accepted.'

    Reset-TestState
    $global:WorkerTestState.UpFailure = $true
    Assert-Fails { Invoke-Setup } 'Compose failed'

    foreach ($case in @(
        @{ Field = 'Rule'; Value = $null; Pattern = 'Falta la regla' },
        @{ Field = 'Running'; Value = $false; Pattern = 'worker activo' },
        @{ Field = 'Health'; Value = 'unhealthy'; Pattern = 'healthy' },
        @{ Field = 'Published'; Value = '0.0.0.0:2222'; Pattern = 'exclusivamente' },
        @{ Field = 'Reachable'; Value = $false; Pattern = 'No se puede abrir TCP' },
        @{ Field = 'Engine'; Value = ''; Pattern = 'Docker Linux no esta listo' }
    )) {
        Reset-TestState
        Invoke-Setup
        $global:WorkerTestState[$case.Field] = $case.Value
        Assert-Fails { Invoke-Setup -CheckOnly } $case.Pattern
        Assert-True ($global:WorkerTestState.Creates -eq 1 -and
            $global:WorkerTestState.Updates -eq 0 -and $global:WorkerTestState.Starts -eq 0 -and
            $global:WorkerTestState.Ups.Count -eq 1) 'A failing CheckOnly changed the machine.'
    }
    foreach ($case in @(
        @{ Field = 'Enabled'; Value = 'False' },
        @{ Field = 'RemoteAddress'; Value = 'Any' },
        @{ Field = 'LocalAddress'; Value = 'Any' },
        @{ Field = 'InterfaceAlias'; Value = 'Any' },
        @{ Field = 'Protocol'; Value = 'UDP' },
        @{ Field = 'LocalPort'; Value = 22 }
    )) {
        Reset-TestState
        Invoke-Setup
        $global:WorkerTestState.Rule.($case.Field) = $case.Value
        Assert-Fails { Invoke-Setup -CheckOnly } 'no coincide'
    }

    Write-Output 'PASS: worker setup, Docker startup, LAN firewall scope, repeat setup, address change, custom port, preview and read-only failure checks.'
}
finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
    if ($hadState) { $global:WorkerTestState = $previousState }
    else { Remove-Variable -Name WorkerTestState -Scope Global -ErrorAction SilentlyContinue }
}
