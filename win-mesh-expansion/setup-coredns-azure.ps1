#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install and configure CoreDNS on an Azure VM for Linkerd mesh expansion.

.DESCRIPTION
    Downloads CoreDNS (if not already present), writes a Corefile that resolves
    standard Linkerd service names to Internal Load Balancer IPs, registers
    CoreDNS as a Windows SCM service, and points the VM's DNS adapter at
    127.0.0.1 so that *.cluster.local names resolve without touching the cluster.

.PARAMETER AutoregIP
    ILB IP for the linkerd-autoregistration service.

.PARAMETER DestinationIP
    ILB IP for the linkerd-destination (linkerd-dst) service.

.PARAMETER PolicyIP
    ILB IP for the linkerd-policy service.

.PARAMETER KubeDnsIP
    ILB IP for kube-dns (used for all other *.cluster.local lookups).

.PARAMETER AutoregName
    FQDN of the linkerd-autoregistration service (the harness resolves this).
    Must match the host part of the installer's CONTROL_ADDRESS property.
    Default: linkerd-autoregistration.linkerd.svc.<ClusterDomain>

.PARAMETER DestinationName
    FQDN of the linkerd-destination (linkerd-dst) service (the proxy resolves this).
    Must match the host part of the installer's DESTINATION_SVC_ADDR property.
    Default: linkerd-dst.linkerd.svc.<ClusterDomain>

.PARAMETER PolicyName
    FQDN of the linkerd-policy service (the proxy resolves this).
    Must match the host part of the installer's POLICY_SVC_ADDR property.
    Default: linkerd-policy.linkerd.svc.<ClusterDomain>

.PARAMETER ClusterDomain
    Cluster domain suffix. Default: cluster.local

.PARAMETER CoreDnsVersion
    CoreDNS release version to download. Default: 1.14.3

.PARAMETER InterfaceAlias
    Network adapter name to update DNS on. Default: Ethernet

.EXAMPLE
    # Standard install (default service names)
    .\setup-coredns-azure.ps1 `
        -AutoregIP   10.224.0.7 `
        -DestinationIP 10.224.0.8 `
        -PolicyIP    10.224.0.9 `
        -KubeDnsIP   10.224.0.10

.EXAMPLE
    # Custom control-plane namespace 'lkd' (must match the installer overrides)
    .\setup-coredns-azure.ps1 `
        -AutoregIP   10.224.0.7 `
        -DestinationIP 10.224.0.8 `
        -PolicyIP    10.224.0.9 `
        -KubeDnsIP   10.224.0.10 `
        -AutoregName     linkerd-autoregistration.lkd.svc.cluster.local `
        -DestinationName linkerd-dst.lkd.svc.cluster.local `
        -PolicyName      linkerd-policy.lkd.svc.cluster.local
#>
param(
    [Parameter(Mandatory)][string]$AutoregIP,
    [Parameter(Mandatory)][string]$DestinationIP,
    [Parameter(Mandatory)][string]$PolicyIP,
    [Parameter(Mandatory)][string]$KubeDnsIP,
    [string]$AutoregName,
    [string]$DestinationName,
    [string]$PolicyName,
    [string]$ClusterDomain  = "cluster.local",
    [string]$CoreDnsVersion = "1.14.3",
    [string]$InterfaceAlias = "Ethernet"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. Derive service-name defaults from the cluster domain.
#    These are the FQDNs the harness/proxy look up; they MUST match the host
#    parts of the installer's CONTROL_ADDRESS / DESTINATION_SVC_ADDR /
#    POLICY_SVC_ADDR properties.  Defaults mirror the installer's own defaults,
#    so the standard install needs no overrides here.  Done in the body because
#    PowerShell param defaults cannot reference another parameter ($ClusterDomain).
# ---------------------------------------------------------------------------
if (-not $AutoregName)     { $AutoregName     = "linkerd-autoregistration.linkerd.svc.$ClusterDomain" }
if (-not $DestinationName) { $DestinationName = "linkerd-dst.linkerd.svc.$ClusterDomain" }
if (-not $PolicyName)      { $PolicyName      = "linkerd-policy.linkerd.svc.$ClusterDomain" }

# ---------------------------------------------------------------------------
# 1. Re-run safety: only if a prior run already pointed the adapter at 127.0.0.1
#    (local CoreDNS) and CoreDNS isn't serving, name resolution is dead and the
#    download below can't resolve github.com. Reset to Azure DNS in that case.
#    On a first run the adapter is already on Azure DNS, so this is a no-op.
# ---------------------------------------------------------------------------
$currentDns = (Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4).ServerAddresses
if ($currentDns -contains "127.0.0.1") {
    Write-Host "DNS points at local CoreDNS; resetting to Azure DNS (168.63.129.16) so the download can resolve..."
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses "168.63.129.16"
    Start-Sleep 2
}

# ---------------------------------------------------------------------------
# 2. Download CoreDNS if not already present
# ---------------------------------------------------------------------------
$coreDnsDir = "C:\coredns"
$coreDnsExe = "$coreDnsDir\coredns.exe"

if (Test-Path $coreDnsExe) {
    Write-Host "CoreDNS binary already present at $coreDnsExe, skipping download."
} else {
    Write-Host "Downloading CoreDNS $CoreDnsVersion..."
    New-Item -ItemType Directory -Force $coreDnsDir | Out-Null
    $zip = "$coreDnsDir\coredns.zip"
    Invoke-WebRequest `
        -Uri "https://github.com/coredns/coredns/releases/download/v$CoreDnsVersion/coredns_${CoreDnsVersion}_windows_amd64.zip" `
        -OutFile $zip
    Expand-Archive $zip -DestinationPath $coreDnsDir -Force
    Remove-Item $zip -Force
    Write-Host "CoreDNS extracted to $coreDnsDir"
}

# ---------------------------------------------------------------------------
# 3. Write Corefile with host overrides for Linkerd ILB IPs
# ---------------------------------------------------------------------------
Write-Host "Writing Corefile..."
$corefile = @"
${ClusterDomain}.:53 {
    bind 127.0.0.1
    hosts {
        $AutoregIP     $AutoregName
        $DestinationIP $DestinationName
        $PolicyIP      $PolicyName
        fallthrough
    }
    forward . ${KubeDnsIP}:53 {
        force_tcp
    }
    log
    errors
}

.:53 {
    bind 127.0.0.1
    forward . 168.63.129.16
    log
    errors
}
"@
$corefile | Out-File -Encoding ascii "$coreDnsDir\Corefile"
Write-Host "Corefile written to $coreDnsDir\Corefile"

# ---------------------------------------------------------------------------
# 4. Register / restart CoreDNS as a Windows SCM service
# ---------------------------------------------------------------------------
$svcName = "coredns"
$existing = sc.exe query $svcName 2>&1
if ($existing -match "RUNNING") {
    Write-Host "Restarting existing CoreDNS service..."
    Stop-Service $svcName -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
} elseif ($existing -notmatch "does not exist") {
    Write-Host "Removing existing CoreDNS service registration..."
    sc.exe stop  $svcName 2>&1 | Out-Null
    sc.exe delete $svcName 2>&1 | Out-Null
    Start-Sleep 2
}

if (-not ($existing -match "RUNNING")) {
    Write-Host "Creating CoreDNS service..."
    sc.exe create $svcName `
        binPath= "$coreDnsExe -conf $coreDnsDir\Corefile -windows-service" `
        start= auto `
        DisplayName= "CoreDNS"
    sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/10000/restart/30000
}

Write-Host "Starting CoreDNS..."
Start-Service $svcName

# ---------------------------------------------------------------------------
# 5. Wait for CoreDNS to be listening on 127.0.0.1:53
# ---------------------------------------------------------------------------
Write-Host "Waiting for CoreDNS to listen on 127.0.0.1:53..."
$deadline = (Get-Date).AddSeconds(30)
while ($true) {
    $result = Test-NetConnection -ComputerName 127.0.0.1 -Port 53 -InformationLevel Quiet -ErrorAction SilentlyContinue
    if ($result) { break }
    if ((Get-Date) -gt $deadline) { throw "CoreDNS did not start within 30 seconds" }
    Start-Sleep 2
}
Write-Host "CoreDNS is listening."

# ---------------------------------------------------------------------------
# 6. Point the VM's DNS adapter at local CoreDNS
# ---------------------------------------------------------------------------
Write-Host "Setting DNS server to 127.0.0.1 on interface '$InterfaceAlias'..."
Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses "127.0.0.1"

# ---------------------------------------------------------------------------
# 7. Verify
# ---------------------------------------------------------------------------
Write-Host "`nVerifying DNS resolution..."
$testName = "kubernetes.default.svc.$ClusterDomain"
$result = Resolve-DnsName -Name $testName -Server 127.0.0.1 -ErrorAction SilentlyContinue
if ($result) {
    Write-Host "OK: $testName -> $($result.IPAddress)"
} else {
    Write-Warning "DNS resolution for $testName failed. Check kube-dns ILB connectivity."
    Write-Warning "  Test-NetConnection $KubeDnsIP -Port 53"
}

Write-Host "`nCoreDNS setup complete."
Write-Host "  Service:  sc query $svcName"
Write-Host "  Corefile: $coreDnsDir\Corefile"