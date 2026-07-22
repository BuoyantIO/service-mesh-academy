#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Register a Faces demo component as a Windows SCM service via WinSW.

.DESCRIPTION
    The Faces demo binaries are plain console apps - they do not implement the
    Windows service control protocol, so they cannot be registered with sc.exe
    directly (SCM would kill them with error 1053). This script wraps a Faces
    component in WinSW (https://github.com/winsw/winsw), giving it a real SCM
    service that:

      - starts automatically at boot AFTER the mesh is up (depends on the
        linkerd-proxy-harness service), so the app never races proxy/driver
        bring-up - this replaces the AtStartup scheduled-task approach and its
        boot delay;
      - restarts on failure; and
      - captures the app's stdout/stderr to rolling log files.

    WinSW uses a rename convention: the wrapper exe and its XML config share a
    basename and sit side by side. This script lays down
    <InstallDir>\faces-<Component>.exe (a copy of WinSW) and
    faces-<Component>.xml, then installs and starts the service.

.PARAMETER Component
    Which Faces component this service runs: smiley | color | face | gui.

.PARAMETER ExePath
    Path to the Faces component binary (e.g. C:\faces-demo\bin\smiley-workload.exe).
    Optional: if omitted, the pinned Faces Windows binaries are downloaded and this
    component's (<Component>-workload.exe) is used.

.PARAMETER FacesVersion
    Faces release to download when -ExePath is omitted. Default: 2.1.0-rc.2.

.PARAMETER Port
    HTTP/gRPC listen port passed to the binary as -port. Defaults per component
    (smiley 8080, color 8081, face 8082, gui 8083).

.PARAMETER EnvVars
    Hashtable of environment variables for the component, e.g.
    @{ FACE_SERVICE = "face.faces.svc.cluster.local" }.

.PARAMETER DependsOn
    SCM service this one must start after. Default: linkerd-proxy-harness.

.PARAMETER InstallDir
    Directory for the WinSW wrapper exe + XML. Default: C:\faces-demo\svc.

.PARAMETER LogDir
    Parent directory for per-component rolling logs. Default: C:\faces-demo\logs.

.PARAMETER WinSwVersion
    WinSW release to download if the wrapper is not already present.
    Default: 2.12.0 (net4 build - runs on Server 2016+/Windows 11 with the
    in-box .NET Framework, no extra runtime install).

.PARAMETER Uninstall
    Stop, uninstall, and remove the service and its wrapper for -Component.

.EXAMPLE
    # VM1 - smiley (HTTP inbound), default wiring
    .\install-faces-service.ps1 -Component smiley -ExePath C:\faces-demo\bin\smiley.exe

.EXAMPLE
    # VM2 - GUI (outbound), pointed at the in-cluster face Service
    .\install-faces-service.ps1 -Component gui -ExePath C:\faces-demo\bin\gui.exe `
        -EnvVars @{ FACE_SERVICE = "face.faces.svc.cluster.local" }

.EXAMPLE
    .\install-faces-service.ps1 -Component smiley -Uninstall
#>
param(
    [Parameter(Mandatory)][ValidateSet('smiley', 'color', 'face', 'gui')][string]$Component,
    [string]$ExePath,
    [int]$Port,
    [hashtable]$EnvVars = @{},
    [string]$DependsOn   = "linkerd-proxy-harness",
    [string]$InstallDir  = "C:\faces-demo\svc",
    [string]$LogDir      = "C:\faces-demo\logs",
    [string]$WinSwVersion = "2.12.0",
    [string]$FacesVersion = "2.1.0-rc.2",
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$serviceId = "faces-$Component"
$wrapperExe = Join-Path $InstallDir "$serviceId.exe"
$wrapperXml = Join-Path $InstallDir "$serviceId.xml"

# ---------------------------------------------------------------------------
# Uninstall path
# ---------------------------------------------------------------------------
if ($Uninstall) {
    if (Test-Path $wrapperExe) {
        Write-Host "Stopping and uninstalling $serviceId..."
        & $wrapperExe stop      2>&1 | Out-Null
        & $wrapperExe uninstall 2>&1 | Out-Null
        Start-Sleep 2
        Remove-Item $wrapperExe, $wrapperXml -Force -ErrorAction SilentlyContinue
        Write-Host "$serviceId removed. Logs left in $LogDir\$Component."
    } else {
        Write-Host "$serviceId not installed (no wrapper at $wrapperExe)."
    }
    return
}

# ---------------------------------------------------------------------------
# Resolve the component binary. If -ExePath wasn't given, download the pinned
# Faces Windows binaries and use this component's (<Component>-workload.exe).
# ---------------------------------------------------------------------------
if (-not $ExePath) {
    $binDir  = "C:\faces-demo\bin"
    $ExePath = Join-Path $binDir "$Component-workload.exe"
    if (-not (Test-Path $ExePath)) {
        Write-Host "Downloading Faces $FacesVersion Windows binaries..."
        New-Item -ItemType Directory -Force $binDir | Out-Null
        $zip = Join-Path $env:TEMP "faces-$FacesVersion-win.zip"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest "https://github.com/BuoyantIO/faces-demo/releases/download/v$FacesVersion/faces-demo_generic_${FacesVersion}_windows_amd64.zip" -OutFile $zip
        Expand-Archive $zip -DestinationPath $binDir -Force
        Remove-Item $zip -Force
    }
    # Fallback in case the archive layout differs from <Component>-workload.exe
    if (-not (Test-Path $ExePath)) {
        $found = Get-ChildItem $binDir -Recurse -Filter "*$Component*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $ExePath = $found.FullName }
    }
}
if (-not (Test-Path $ExePath))  { throw "Faces binary not found: $ExePath" }
$ExePath = (Resolve-Path $ExePath).Path

if (-not $Port) {
    $Port = @{ smiley = 8080; color = 8081; face = 8082; gui = 8083 }[$Component]
}

$componentLogDir = Join-Path $LogDir $Component
New-Item -ItemType Directory -Force $InstallDir      | Out-Null
New-Item -ItemType Directory -Force $componentLogDir | Out-Null

# ---------------------------------------------------------------------------
# Fetch WinSW wrapper if not already present (pinned version)
# ---------------------------------------------------------------------------
if (Test-Path $wrapperExe) {
    Write-Host "WinSW wrapper already present at $wrapperExe."
} else {
    $url = "https://github.com/winsw/winsw/releases/download/v$WinSwVersion/WinSW-x64.exe"
    Write-Host "Downloading WinSW $WinSwVersion..."
    Invoke-WebRequest -Uri $url -OutFile $wrapperExe
    Write-Host "WinSW downloaded to $wrapperExe."
}

# ---------------------------------------------------------------------------
# Generate the WinSW manifest
# ---------------------------------------------------------------------------
$envLines = ($EnvVars.GetEnumerator() | ForEach-Object {
    "  <env name=""$($_.Key)"" value=""$($_.Value)"" />"
}) -join "`n"

$xml = @"
<service>
  <id>$serviceId</id>
  <name>Faces $Component</name>
  <description>Faces demo '$Component' component, mesh-expanded via Linkerd (BEL WME).</description>
  <executable>$ExePath</executable>
  <arguments>-port $Port</arguments>
  <workingdirectory>$(Split-Path $ExePath -Parent)</workingdirectory>
  <startmode>Automatic</startmode>
  <depend>$DependsOn</depend>
  <onfailure action="restart" delay="10 sec" />
  <resetfailure>1 hour</resetfailure>
  <log mode="roll-by-size">
    <logpath>$componentLogDir</logpath>
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>8</keepFiles>
  </log>
$envLines
</service>
"@
$xml | Out-File -Encoding utf8 $wrapperXml
Write-Host "Wrote WinSW manifest: $wrapperXml"

# ---------------------------------------------------------------------------
# (Re)install and start the service
# ---------------------------------------------------------------------------
if ((& $wrapperExe status 2>&1) -notmatch "NonExistent") {
    Write-Host "Service $serviceId already registered - reinstalling..."
    & $wrapperExe stop      2>&1 | Out-Null
    & $wrapperExe uninstall 2>&1 | Out-Null
    Start-Sleep 2
}

Write-Host "Installing service $serviceId..."
& $wrapperExe install
& $wrapperExe start

Start-Sleep 3
$state = (sc.exe query $serviceId) -match "RUNNING"
if ($state) {
    Write-Host "`n$serviceId is RUNNING."
} else {
    Write-Warning "$serviceId did not reach RUNNING. Check logs:"
    Write-Warning "  $componentLogDir\$serviceId.out.log"
    Write-Warning "  $componentLogDir\$serviceId.err.log"
}

Write-Host "  Service:  sc query $serviceId"
Write-Host "  Manifest: $wrapperXml"
Write-Host "  Logs:     $componentLogDir\$serviceId.{out,err,wrapper}.log"
