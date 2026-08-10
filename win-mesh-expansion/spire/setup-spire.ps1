#Requires -RunAsAdministrator
# Sets up SPIRE on a Windows VM for BEL Windows Mesh Expansion.
#
#   -Role Server  the dedicated SPIRE server VM. It alone holds the upstream CA
#                 key, binds 0.0.0.0:8081, and issues SVIDs for every other VM.
#                 It runs no workload and no agent.
#
#   -Role Agent   a meshed workload VM. Runs spire-agent only: it verifies the
#                 server against the trust bundle and never holds a CA key, so
#                 compromising a workload VM cannot mint identities.
#
# The server is set up once; each workload VM then needs a one-shot join token
# and a workload entry, both created on the server VM (see README Part 2).
param(
    [Parameter(Mandatory)][ValidateSet('Server', 'Agent')][string]$Role,

    # Both roles: upstream CA cert + Linkerd root CA, concatenated. The agent
    # verifies the server against this; the server publishes it in its bundle.
    [Parameter(Mandatory)][string]$BundleCert,

    # -Role Server only.
    [string]$CACert,                          # SPIRE upstream CA cert (pathlen:1)
    [string]$CAKey,                           #   ...its private key
    [string]$AllowFromCidr = "10.20.0.0/24",  # who may reach 8081 (the VM subnet)

    # -Role Agent only.
    [string]$ServerAddress,                   # the SPIRE server VM's private IP
    [string]$JoinToken,                       # one-shot, from `token generate`

    [string]$SpireVersion = "1.15.2"
)

$ErrorActionPreference = 'Stop'

# 0. Role-specific argument checks, up front - a half-configured SPIRE is much
#    harder to diagnose than a refusal to start.
if ($Role -eq 'Server') {
    if (-not $CACert -or -not $CAKey) { throw "-Role Server requires -CACert and -CAKey" }
    if ($ServerAddress -or $JoinToken) { throw "-ServerAddress/-JoinToken are for -Role Agent" }
} else {
    if (-not $ServerAddress -or -not $JoinToken) { throw "-Role Agent requires -ServerAddress and -JoinToken" }
    if ($CACert -or $CAKey) { throw "-CACert/-CAKey must NOT be given to an agent - a workload VM never holds a CA key" }
}

# 1. Install the config(s) to C:\spire so the VM stays self-contained after the
#    staging folder (e.g. C:\temp\spire) is deleted.
New-Item -ItemType Directory -Force C:\spire | Out-Null
$cfg = if ($Role -eq 'Server') { "server.cfg" } else { "agent.cfg" }
if ((Resolve-Path "$PSScriptRoot\$cfg").Path -ne "C:\spire\$cfg") { Copy-Item "$PSScriptRoot\$cfg" "C:\spire\$cfg" -Force }

# An agent points at the server VM; the shipped agent.cfg defaults to loopback.
if ($Role -eq 'Agent') {
    (Get-Content C:\spire\agent.cfg) -replace '(server_address\s*=\s*)"[^"]*"', "`$1`"$ServerAddress`"" |
        Set-Content -Encoding ascii C:\spire\agent.cfg
}

# 2. SPIRE binaries - download the pinned release if not already present. The
#    agent role deliberately does not install spire-server.exe.
$bin = "C:\spire\bin"
$need = if ($Role -eq 'Server') { @("spire-server.exe", "spire-agent.exe") } else { @("spire-agent.exe") }
New-Item -ItemType Directory -Force $bin | Out-Null
if ($need | Where-Object { -not (Test-Path "$bin\$_") }) {
    Write-Host "Downloading SPIRE $SpireVersion..."
    $url = "https://github.com/spiffe/spire/releases/download/v$SpireVersion/spire-$SpireVersion-windows-amd64.zip"
    $zip = "$env:TEMP\spire-$SpireVersion.zip"
    $tmp = "$env:TEMP\spire-$SpireVersion"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $zip
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $zip -DestinationPath $tmp -Force
    foreach ($exe in $need) {
        Copy-Item (Get-ChildItem $tmp -Recurse -Filter $exe)[0].FullName "$bin\$exe" -Force
    }
    Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# 3. Stage the cert files at the paths the configs expect (skip if already there).
New-Item -ItemType Directory -Force C:\spire\certs | Out-Null
if ((Resolve-Path $BundleCert).Path -ne "C:\spire\certs\bundle.crt") { Copy-Item $BundleCert C:\spire\certs\bundle.crt -Force }
if ($Role -eq 'Server') {
    if ((Resolve-Path $CACert).Path -ne "C:\spire\certs\ca.crt") { Copy-Item $CACert C:\spire\certs\ca.crt -Force }
    if ((Resolve-Path $CAKey).Path  -ne "C:\spire\certs\ca.key") { Copy-Item $CAKey  C:\spire\certs\ca.key -Force }

    # This directory now holds the upstream CA private key - the one secret on
    # any VM that could mint identities for the whole trust domain. Drop
    # inherited ACLs so only SYSTEM (which SPIRE runs as) and Administrators
    # can read it, rather than whatever C:\ happens to grant.
    icacls C:\spire\certs /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" /T /C | Out-Null
}

# 4. Data/log dirs, writable by SYSTEM (SPIRE runs as LocalSystem). This must
#    happen BEFORE anything writes there, so the SVID files the bootstrap
#    creates inherit an ACL the service account can still read.
New-Item -ItemType Directory -Force C:\spire\logs | Out-Null
New-Item -ItemType Directory -Force (@{Server = "C:\spire\data\server"; Agent = "C:\spire\data\agent" }[$Role]) | Out-Null
icacls C:\spire\data /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /T /C | Out-Null

if ($Role -eq 'Server') {
    # 5a. Let the workload VMs' agents reach the server. The MSI adds no
    #     firewall rules, and Windows defaults inbound to Block.
    $ruleName = "SPIRE server 8081"
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort 8081 -RemoteAddress $AllowFromCidr | Out-Null

    # 6a. Install the server as an SCM service. start= auto brings it back at
    #     boot; the workload VMs' agents depend on it being reachable, so it
    #     must come up without human help.
    sc.exe stop spire-server 2>&1 | Out-Null; sc.exe delete spire-server 2>&1 | Out-Null
    sc.exe create spire-server binPath= "C:\spire\bin\spire-server.exe run -config C:\spire\server.cfg" start= auto obj= LocalSystem DisplayName= "SPIRE Server" | Out-Null
    sc.exe failure spire-server reset= 86400 actions= restart/5000/restart/15000/restart/60000 | Out-Null
    sc.exe start spire-server | Out-Null

    $deadline = (Get-Date).AddSeconds(60)
    while (((sc.exe query spire-server) -notmatch "RUNNING") -and (Get-Date) -lt $deadline) { Start-Sleep 2 }
    if ((sc.exe query spire-server) -notmatch "RUNNING") { throw "SPIRE server did not start (check C:\spire\logs\server.log)" }

    Write-Host "SPIRE server ready on 0.0.0.0:8081, reachable from $AllowFromCidr."
    Write-Host "For each workload VM, run here:"
    Write-Host "  C:\spire\bin\spire-server.exe entry create -parentID spiffe://cluster.local/agent/<vm> -spiffeID spiffe://cluster.local/<workload> -selector `"windows:user_name:NT AUTHORITY\SYSTEM`""
    Write-Host "  C:\spire\bin\spire-server.exe token generate -spiffeID spiffe://cluster.local/agent/<vm>"
}
else {
    # 5b. One-shot bootstrap: attest with the join token so an SVID lands on
    #     disk, then stop. Join-token attestation is not re-attestable, so the
    #     service below must resume on that SVID rather than re-run the token.
    Write-Host "Bootstrapping agent against $ServerAddress..."
    $agent = Start-Process -NoNewWindow -PassThru C:\spire\bin\spire-agent.exe -ArgumentList run, -config, C:\spire\agent.cfg, -joinToken, $JoinToken
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path "\\.\pipe\spire-agent\public\api")) {
        if ((Get-Date) -gt $deadline) { throw "Agent did not attest (check C:\spire\logs\agent.log - expired token, or 8081 blocked on the server VM)" }
        Start-Sleep 2
    }
    Stop-Process -Id $agent.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep 2

    # 6b. Install the agent as an SCM service. Deliberately NO depend= here:
    #     there is no local spire-server. If the server VM or the network is not
    #     ready at boot, the failure actions retry.
    sc.exe stop spire-agent 2>&1 | Out-Null; sc.exe delete spire-agent 2>&1 | Out-Null
    sc.exe create spire-agent binPath= "C:\spire\bin\spire-agent.exe run -config C:\spire\agent.cfg" start= auto obj= LocalSystem DisplayName= "SPIRE Agent" | Out-Null
    sc.exe failure spire-agent reset= 86400 actions= restart/5000/restart/15000/restart/60000 | Out-Null
    sc.exe start spire-agent | Out-Null

    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path "\\.\pipe\spire-agent\public\api")) {
        if ((Get-Date) -gt $deadline) { throw "Timed out waiting for SPIRE agent pipe (check C:\spire\logs\agent.log)" }
        Start-Sleep 2
    }
    Write-Host "SPIRE agent ready: attested to $ServerAddress, workload pipe up."
}
