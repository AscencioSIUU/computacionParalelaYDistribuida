[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BindAddress,
    [ValidateRange(1, 65535)]
    [int]$Port = 2222,
    [ValidateRange(30, 600)]
    [int]$StartupTimeoutSeconds = 180,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

function Get-DockerEngine {
    $result = & docker info --format '{{.OSType}}' 2>$null
    if ($LASTEXITCODE -eq 0) { return "$result".Trim() }
    return ''
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker Desktop no esta instalado o docker no esta en PATH.'
}

$addresses = @(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
    ForEach-Object { $_.IPv4Address } |
    Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notlike '169.254.*' })
if ($BindAddress) {
    $addresses = @($addresses | Where-Object { $_.IPAddress -eq $BindAddress })
}
if ($addresses.Count -ne 1) {
    throw 'No hay una unica IPv4 LAN activa. Se debe indicar -BindAddress con la IPv4 de la interfaz que tiene la puerta de enlace.'
}
$address = $addresses[0]
$BindAddress = $address.IPAddress
$interface = Get-NetAdapter -InterfaceIndex $address.InterfaceIndex
$profile = Get-NetConnectionProfile -InterfaceIndex $address.InterfaceIndex -ErrorAction SilentlyContinue
$ruleName = "CC3069-MPI-Worker-$Port"

$endpoint = & docker context inspect --format '{{.Endpoints.docker.Host}}'
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar el contexto Docker.' }
if ($env:DOCKER_HOST -and -not $env:DOCKER_CONTEXT) { $endpoint = $env:DOCKER_HOST }
if ("$endpoint" -notlike 'npipe://*') {
    throw 'Se requiere Docker Desktop local mediante una named pipe de Windows, no un motor remoto.'
}

Write-Output "Worker LAN: ${BindAddress}:$Port, interfaz $($interface.Name)."
if ($profile) { Write-Output "Perfil de red: $($profile.NetworkCategory). No se modifica." }

if (-not $CheckOnly) {
    if (-not $PSCmdlet.ShouldProcess("${BindAddress}:$Port",
        'Permitir SSH desde LocalSubnet en el firewall, iniciar Docker Desktop y levantar solo el worker')) {
        return
    }

    $firewall = @{
        Name = $ruleName
        Description = 'SSH del worker MPI desde la subred local. MPI utiliza el tunel SSH.'
        Enabled = 'True'
        Direction = 'Inbound'
        Action = 'Allow'
        Profile = 'Any'
        InterfaceAlias = $interface.Name
        Protocol = 'TCP'
        LocalPort = $Port
        RemotePort = 'Any'
        LocalAddress = $BindAddress
        RemoteAddress = 'LocalSubnet'
        EdgeTraversalPolicy = 'Block'
    }
    try {
        if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
            Set-NetFirewallRule @firewall -ErrorAction Stop | Out-Null
        }
        else {
            New-NetFirewallRule @firewall -DisplayName "CC3069 MPI worker TCP $Port" -ErrorAction Stop | Out-Null
        }
    }
    catch {
        throw "No se pudo configurar el firewall. Se requiere PowerShell como administrador. $($_.Exception.Message)"
    }

    $engine = Get-DockerEngine
    if (-not $engine) {
        Write-Output 'Iniciando Docker Desktop...'
        & docker desktop start --timeout $StartupTimeoutSeconds
        if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop no pudo iniciar. Se debe revisar su instalacion y WSL 2.' }
        $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
        do {
            $engine = Get-DockerEngine
            if ($engine) { break }
            Start-Sleep -Seconds 2
        } while ([DateTime]::UtcNow -lt $deadline)
    }
    if ($engine -ne 'linux') { throw 'Docker debe estar listo y configurado para Linux containers.' }

    & "$PSScriptRoot\desktop.ps1" up -Role worker -BindAddress $BindAddress -Port $Port
}

$failures = [System.Collections.Generic.List[string]]::new()
if ((Get-DockerEngine) -ne 'linux') { $failures.Add('Docker Linux no esta listo.') }

$rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
if ($rule) {
    $ports = $rule | Get-NetFirewallPortFilter
    $scope = $rule | Get-NetFirewallAddressFilter
    $interfaces = $rule | Get-NetFirewallInterfaceFilter
    if ($rule.Enabled -ne 'True' -or $rule.Direction -ne 'Inbound' -or
        $rule.Action -ne 'Allow' -or $rule.Profile -ne 'Any' -or
        $ports.Protocol -ne 'TCP' -or "$($ports.LocalPort)" -ne "$Port" -or
        "$($scope.LocalAddress)" -ne $BindAddress -or
        "$($scope.RemoteAddress)" -ne 'LocalSubnet' -or
        "$($interfaces.InterfaceAlias)" -ne $interface.Name) {
        $failures.Add("La regla $ruleName no coincide con la interfaz, el puerto y la subred requeridos.")
    }
}
else {
    $failures.Add("Falta la regla de firewall $ruleName. Se requiere ejecutar el script como administrador.")
}

$container = @(& docker ps --filter 'label=com.docker.compose.project=cc3069-desktop' `
    --filter 'label=com.docker.compose.service=worker' --format '{{.ID}}')
if ($LASTEXITCODE -ne 0 -or $container.Count -ne 1) {
    $failures.Add('No hay un unico worker activo del proyecto cc3069-desktop.')
}
else {
    $health = & docker inspect --format '{{.State.Health.Status}}' $container[0]
    if ($LASTEXITCODE -ne 0 -or $health -ne 'healthy') { $failures.Add('El worker no esta healthy.') }
    $published = & docker port $container[0] 22/tcp
    if ($LASTEXITCODE -ne 0 -or "$published".Trim() -ne "${BindAddress}:$Port") {
        $failures.Add('El worker no publica SSH exclusivamente en la IPv4 LAN y el puerto elegidos.')
    }
}
if (-not (Test-NetConnection -ComputerName $BindAddress -Port $Port `
    -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    $failures.Add("No se puede abrir TCP hacia ${BindAddress}:$Port desde esta maquina.")
}
if ($failures.Count) {
    throw ($failures -join "`n")
}

Write-Output 'PASS: Docker Linux, worker healthy, puerto LAN y regla LocalSubnet.'
Write-Output 'La prueba local no demuestra acceso desde otra computadora ni evita el aislamiento Wi-Fi.'
Write-Output 'Identidad publica: .\desktop.ps1 identity -Role worker'
Write-Output 'El maestro debe verificar e intercambiar identidades antes de conectar.'
Write-Output "Conexion desde el maestro: .\desktop.ps1 connect -PeerAddress $BindAddress -Port $Port"
Write-Output 'Con varios workers, el maestro debe usar un -WorkerId unico al registrar cada identidad y conectar.'
