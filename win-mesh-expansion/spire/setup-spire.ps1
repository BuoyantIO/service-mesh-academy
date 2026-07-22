#Requires -RunAsAdministrator
# Sets up SPIRE (server + agent) on a Windows VM for BEL Windows Mesh Expansion:
# downloads the pinned SPIRE release, bootstraps a per-VM server backed by the
# upstream CA, registers this VM's workload SPIFFE ID, and installs SCM services
# that bring SPIRE up at boot.
param(
    [Parameter(Mandatory)][string]$CACert,      # SPIRE upstream CA cert (chains to the cluster root)
    [Parameter(Mandatory)][string]$CAKey,       #   ...its private key
    [Parameter(Mandatory)][string]$BundleCert,  # upstream CA cert + cluster root CA, concatenated
    # Give each VM its own identity (e.g. .../smiley, .../faces-gui) so cluster
    # policy can authorize each precisely; all VMs share the upstream CA.
    [string]$WorkloadSpiffeId = "spiffe://cluster.local/external-workload",
    [string]$SpireVersion     = "1.15.2"
)

$ErrorActionPreference = 'Stop'

# 0. Install the configs to C:\spire so it stays self-contained after the
#    staging folder (e.g. C:\temp\spire) is deleted.
New-Item -ItemType Directory -Force C:\spire | Out-Null
foreach ($f in "server.cfg", "agent.cfg") {
    if ((Resolve-Path "$PSScriptRoot\$f").Path -ne "C:\spire\$f") { Copy-Item "$PSScriptRoot\$f" "C:\spire\$f" -Force }
}

# 1. SPIRE binaries - download the pinned release if not already present.
$bin = "C:\spire\bin"
New-Item -ItemType Directory -Force $bin | Out-Null
if (-not (Test-Path "$bin\spire-server.exe") -or -not (Test-Path "$bin\spire-agent.exe")) {
    Write-Host "Downloading SPIRE $SpireVersion..."
    $url = "https://github.com/spiffe/spire/releases/download/v$SpireVersion/spire-$SpireVersion-windows-amd64.zip"
    $zip = "$env:TEMP\spire-$SpireVersion.zip"
    $tmp = "$env:TEMP\spire-$SpireVersion"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $zip
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $zip -DestinationPath $tmp -Force
    Copy-Item (Get-ChildItem $tmp -Recurse -Filter spire-server.exe)[0].FullName "$bin\spire-server.exe" -Force
    Copy-Item (Get-ChildItem $tmp -Recurse -Filter spire-agent.exe)[0].FullName  "$bin\spire-agent.exe"  -Force
    Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# 2. Stage the cert files at the paths server.cfg expects (skip if already there).
New-Item -ItemType Directory -Force C:\spire\certs | Out-Null
if ((Resolve-Path $CACert).Path     -ne "C:\spire\certs\ca.crt")     { Copy-Item $CACert     C:\spire\certs\ca.crt     -Force }
if ((Resolve-Path $CAKey).Path      -ne "C:\spire\certs\ca.key")     { Copy-Item $CAKey      C:\spire\certs\ca.key     -Force }
if ((Resolve-Path $BundleCert).Path -ne "C:\spire\certs\bundle.crt") { Copy-Item $BundleCert C:\spire\certs\bundle.crt -Force }

# 3. Data/log dirs, writable by SYSTEM (SPIRE runs as LocalSystem).
New-Item -ItemType Directory -Force C:\spire\logs, C:\spire\data\server, C:\spire\data\agent | Out-Null
icacls C:\spire\data /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /T /C | Out-Null

# 4. One-time bootstrap: start server, mint a join token, attest the agent,
#    register the workload entry, then stop (the SCM services take over from here).
Write-Host "Bootstrapping SPIRE..."
$server = Start-Process -NoNewWindow -PassThru C:\spire\bin\spire-server.exe -ArgumentList run,-config,C:\spire\server.cfg
Start-Sleep 10
$token = (& C:\spire\bin\spire-server.exe token generate -spiffeID spiffe://cluster.local/agent -output json | ConvertFrom-Json).value
if (-not $token) { throw "Failed to generate SPIRE join token" }
$agent = Start-Process -NoNewWindow -PassThru C:\spire\bin\spire-agent.exe -ArgumentList run,-config,C:\spire\agent.cfg,-joinToken,$token
Start-Sleep 15
& C:\spire\bin\spire-server.exe entry create -parentID spiffe://cluster.local/agent -spiffeID $WorkloadSpiffeId -selector "windows:user_name:NT AUTHORITY\SYSTEM"
Stop-Process -Id $server.Id, $agent.Id -Force -ErrorAction SilentlyContinue
Start-Sleep 2

# 5. Install SCM services (idempotent). Args are baked into binPath, start is
#    'auto', and the agent depends on the server - so SCM brings both up in
#    dependency order at every boot, with no scheduled task or boot script.
sc.exe stop spire-agent  2>&1 | Out-Null; sc.exe delete spire-agent  2>&1 | Out-Null
sc.exe stop spire-server 2>&1 | Out-Null; sc.exe delete spire-server 2>&1 | Out-Null
sc.exe create spire-server binPath= "C:\spire\bin\spire-server.exe run -config C:\spire\server.cfg" start= auto obj= LocalSystem DisplayName= "SPIRE Server" | Out-Null
sc.exe failure spire-server reset= 86400 actions= restart/5000/restart/15000/restart/60000 | Out-Null
sc.exe create spire-agent binPath= "C:\spire\bin\spire-agent.exe run -config C:\spire\agent.cfg" start= auto depend= spire-server obj= LocalSystem DisplayName= "SPIRE Agent" | Out-Null
sc.exe failure spire-agent reset= 86400 actions= restart/5000/restart/15000/restart/60000 | Out-Null

# 6. Start now (start= auto brings them back on later boots); wait for the agent pipe.
sc.exe start spire-server | Out-Null
$srvDeadline = (Get-Date).AddSeconds(30)
while (((sc.exe query spire-server) -notmatch "RUNNING") -and (Get-Date) -lt $srvDeadline) { Start-Sleep 2 }
sc.exe start spire-agent | Out-Null

$deadline = (Get-Date).AddSeconds(60)
while (-not (Test-Path "\\.\pipe\spire-agent\public\api")) {
    if ((Get-Date) -gt $deadline) { throw "Timed out waiting for SPIRE agent pipe (check C:\spire\logs)" }
    Start-Sleep 2
}
Write-Host "SPIRE ready: workload $WorkloadSpiffeId, agent pipe up."
