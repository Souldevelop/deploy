<#
.SYNOPSIS
    Claude Code CLI Windows 一键安装引导脚本
.DESCRIPTION
    自动从镜像仓库下载部署脚本和配置文件并执行，无需 Git。
    支持远程执行（免下载仓库）:

    Gitee:
        powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object Net.WebClient).DownloadString('https://gitee.com/reverseking/deploy/raw/master/install.ps1'))"

    GitHub:
        powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/Souldevelop/deploy/master/install.ps1'))"

.PARAMETER Mirror
    Mirror source: auto (default), gitee, github
#>

param(
    [Alias('m')]
    [string]$Mirror = "auto"
)

$ErrorActionPreference = "Stop"

# Fix console encoding for Chinese output
chcp 65001 > $null

$giteeBase = "https://gitee.com/reverseking/deploy/raw/master"
$githubBase = "https://raw.githubusercontent.com/Souldevelop/deploy/master"

Write-Host "=== Claude Code CLI Windows Installer ==="
Write-Host ""

# ---- mirror detection ----
$baseUrl = ""
if ($Mirror -eq "gitee") {
    $baseUrl = $giteeBase
    Write-Host "[OK] Mirror: Gitee (--mirror gitee)"
} elseif ($Mirror -eq "github") {
    $baseUrl = $githubBase
    Write-Host "[OK] Mirror: GitHub (--mirror github)"
} else {
    Write-Host "[..] Detecting best mirror ..."
    try {
        $req = [Net.WebRequest]::Create("$giteeBase/deploy.ps1")
        $req.Timeout = 3000
        $resp = $req.GetResponse()
        $resp.Close()
        $baseUrl = $giteeBase
        Write-Host "[OK] Mirror: Gitee (fast)"
    } catch {
        $baseUrl = $githubBase
        Write-Host "[OK] Mirror: GitHub (Gitee unreachable)"
    }
}
Write-Host ""

# ---- download ----
$wc = New-Object Net.WebClient
$confPath = "$env:TEMP\deploy.conf"
$scriptPath = "$env:TEMP\deploy_claude.ps1"

Write-Host "[..] Downloading deploy.conf ..."
$wc.DownloadFile("$baseUrl/deploy.conf", $confPath)
Write-Host "[OK]  $confPath"

Write-Host "[..] Downloading deploy.ps1 ..."
$wc.DownloadFile("$baseUrl/deploy.ps1", $scriptPath)
Write-Host "[OK]  $scriptPath"
Write-Host ""

# ---- launch installer (elevated, same window) ----
Write-Host "[..] Launching installer (admin may prompt UAC) ..."
try {
    $p = Start-Process powershell -Verb RunAs -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $scriptPath,
        "-ConfigFile", $confPath
    ) -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Host "[ER] Installer exited with code $($p.ExitCode)"
    } else {
        Write-Host "[OK] Installation completed"
    }
} catch {
    Write-Host "[ER] Failed to start installer: $_"
}

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Close this window or run: exit"
