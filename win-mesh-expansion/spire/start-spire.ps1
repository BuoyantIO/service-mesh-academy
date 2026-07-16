# Starts spire-server -> spire-agent -> linkerd-proxy-harness in dependency order.
# Registered as the "SpireStartup" scheduled task (SYSTEM, AtStartup).
$log = "C:\spire\logs\startup.log"
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null

function Wait-ServiceRunning {
    param($Name, $TimeoutSec = 60)
    $end = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $end) {
        if ((sc.exe query $Name) -match "RUNNING") { return $true }
        Start-Sleep 2
    }
    return $false
}

"$(Get-Date) starting spire-server" | Add-Content $log
sc.exe start spire-server run -config C:\spire\server.cfg

if (Wait-ServiceRunning spire-server) {
    "$(Get-Date) spire-server RUNNING, starting spire-agent" | Add-Content $log
    sc.exe start spire-agent run -config C:\spire\agent.cfg -retryBootstrap

    if (Wait-ServiceRunning spire-agent) {
        "$(Get-Date) spire-agent RUNNING, starting harness" | Add-Content $log
        sc.exe start linkerd-proxy-harness
        "$(Get-Date) startup complete" | Add-Content $log
    } else {
        "$(Get-Date) ERROR: spire-agent did not reach RUNNING within 60s" | Add-Content $log
    }
} else {
    "$(Get-Date) ERROR: spire-server did not reach RUNNING within 60s" | Add-Content $log
}
