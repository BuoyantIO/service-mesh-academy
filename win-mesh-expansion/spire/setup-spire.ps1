#Requires -RunAsAdministrator
param(
    [string]$Namespace = "linkerd",
    [Parameter(Mandatory)][string]$CACert,
    [Parameter(Mandatory)][string]$CAKey,
    [Parameter(Mandatory)][string]$BundleCert,
    # SPIFFE ID registered for this VM's workload. Give each VM its own identity
    # (e.g. spiffe://cluster.local/smiley, .../faces-gui) so cluster policy can
    # authorize each VM precisely. All VMs still share the upstream CA
    # intermediate, so every SVID chains to the same root (see docs/spire.md).
    [string]$WorkloadSpiffeId = "spiffe://cluster.local/external-workload"
)

$ErrorActionPreference = 'Stop'

# 1. Verify SPIRE binaries are present — copy the spire folder from the repo and
#    the bin\ directory from a prior SUT before running this script.
foreach ($bin in @("C:\spire\bin\spire-server.exe", "C:\spire\bin\spire-agent.exe")) {
    if (-not (Test-Path $bin)) { throw "Missing binary: $bin - copy bin\ from a prior SUT before running setup." }
}

# 2. Verify required cert files are present and copy to canonical locations.
#    CACert / CAKey  = SPIRE upstream CA (chained to cluster root for AKS, self-signed for k3d).
#    BundleCert      = CACert + root-ca.crt concatenated (see docs/spire.md).
New-Item -ItemType Directory -Force C:\spire\certs | Out-Null
if (-not (Test-Path $CACert))     { throw "Missing CACert: $CACert" }
if (-not (Test-Path $CAKey))      { throw "Missing CAKey: $CAKey" }
if (-not (Test-Path $BundleCert)) { throw "Missing BundleCert: $BundleCert" }

if ($CACert     -ne "C:\spire\certs\ca.crt")     { Copy-Item $CACert     "C:\spire\certs\ca.crt"    -Force }
if ($CAKey      -ne "C:\spire\certs\ca.key")      { Copy-Item $CAKey      "C:\spire\certs\ca.key"    -Force }
if ($BundleCert -ne "C:\spire\certs\bundle.crt")  { Copy-Item $BundleCert "C:\spire\certs\bundle.crt" -Force }
Write-Host "SPIRE certs verified."

# 3. Create required directories and fix permissions so SYSTEM can write data/logs.
New-Item -ItemType Directory -Force C:\spire\logs        | Out-Null
New-Item -ItemType Directory -Force C:\spire\data\server | Out-Null
New-Item -ItemType Directory -Force C:\spire\data\agent  | Out-Null
icacls "C:\spire\data" /grant "Administrators:(OI)(CI)F" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" /T /C | Out-Null

# 4. Bootstrap — start server, create join token, start agent, register workload entry, then stop.
#    After this the agent re-attests on each subsequent start without a new token.
Write-Host "Bootstrapping SPIRE..."

$serverProc = Start-Process -NoNewWindow -PassThru `
    -FilePath "C:\spire\bin\spire-server.exe" `
    -ArgumentList "run", "-config", "C:\spire\server.cfg"

Write-Host "Waiting for server..."
Start-Sleep 10

$tokenJson = & "C:\spire\bin\spire-server.exe" token generate `
    -spiffeID spiffe://cluster.local/agent -output json | ConvertFrom-Json
$token = $tokenJson.value
if (-not $token) { throw "Failed to generate SPIRE join token" }

$agentProc = Start-Process -NoNewWindow -PassThru `
    -FilePath "C:\spire\bin\spire-agent.exe" `
    -ArgumentList "run", "-config", "C:\spire\agent.cfg", "-joinToken", $token

Write-Host "Waiting for agent to attest..."
Start-Sleep 15

& "C:\spire\bin\spire-server.exe" entry create `
    -parentID spiffe://cluster.local/agent `
    -spiffeID $WorkloadSpiffeId `
    -selector "windows:user_name:NT AUTHORITY\SYSTEM"

Write-Host "Registered workload SPIFFE ID: $WorkloadSpiffeId"

Write-Host "Stopping server and agent (SCM services manage startup from here)..."
Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $agentProc.Id  -Force -ErrorAction SilentlyContinue
Start-Sleep 2

# 5. Register SCM services (clean up any prior install first)
Write-Host "Registering SCM services..."
$null = sc.exe stop spire-agent  2>&1; $null = sc.exe delete spire-agent  2>&1
$null = sc.exe stop spire-server 2>&1; $null = sc.exe delete spire-server 2>&1

sc.exe create spire-server binPath= "C:\spire\bin\spire-server.exe" start= demand obj= LocalSystem DisplayName= "SPIRE Server"
sc.exe failure spire-server reset= 86400 actions= run/5000/run/15000/run/60000 command= "C:\Windows\System32\sc.exe start spire-server run -config C:\spire\server.cfg"

sc.exe create spire-agent binPath= "C:\spire\bin\spire-agent.exe" start= demand depend= spire-server obj= LocalSystem DisplayName= "SPIRE Agent"
sc.exe failure spire-agent reset= 86400 actions= run/5000/run/15000/run/60000 command= "C:\Windows\System32\sc.exe start spire-agent run -config C:\spire\agent.cfg -retryBootstrap"

# 6. Register SpireStartup scheduled task
Write-Host "Registering SpireStartup scheduled task..."
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                 -Argument "-NonInteractive -ExecutionPolicy Bypass -File C:\spire\start-spire.ps1" `
                 -WorkingDirectory "C:\spire"
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName "SpireStartup" -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "Starting SPIRE via SpireStartup task..."
Start-ScheduledTask -TaskName SpireStartup

Write-Host "Waiting for SPIRE agent pipe..."
$deadline = (Get-Date).AddSeconds(60)
while (-not (Test-Path "\\.\pipe\spire-agent\public\api")) {
    if ((Get-Date) -gt $deadline) { throw "Timed out waiting for SPIRE agent pipe" }
    Start-Sleep 2
}
Write-Host "SPIRE agent pipe ready."

$serverRunning = (sc.exe query spire-server) -match "RUNNING"
$agentRunning  = (sc.exe query spire-agent)  -match "RUNNING"
$pipeReady     = Test-Path "\\.\pipe\spire-agent\public\api"

if ($serverRunning -and $agentRunning -and $pipeReady) {
    Write-Host "SPIRE setup complete and running."
} else {
    Write-Host "WARNING: SPIRE may not be fully running. Check logs:"
    Write-Host "  C:\spire\logs\server.log"
    Write-Host "  C:\spire\logs\agent.log"
    sc.exe query spire-server
    sc.exe query spire-agent
}
