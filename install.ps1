<#
.SYNOPSIS
    Claude Code CLI Windows 一键安装引导脚本
.DESCRIPTION
    自动从镜像仓库下载部署脚本和配置文件并执行，无需 Git。
    支持远程执行（免下载仓库）:

    Gitee（中国大陆推荐）:
        powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object Net.WebClient).DownloadString('https://gitee.com/reverseking/deploy/raw/master/install.ps1'))"

    GitHub:
        powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/Souldevelop/deploy/master/install.ps1'))"

.PARAMETER Mirror
    镜像源: auto（自动检测）, gitee, github。默认 auto。
#>

param(
    [Alias('m')]
    [string]$Mirror = "auto"
)

$ErrorActionPreference = "Stop"

$giteeBase = "https://gitee.com/reverseking/deploy/raw/master"
$githubBase = "https://raw.githubusercontent.com/Souldevelop/deploy/master"

Write-Host "=== Claude Code CLI Windows 一键安装 ==="
Write-Host ""

# ---- 镜像检测 ----
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

# ---- 下载部署脚本 ----
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

# ---- 启动安装器 ----
Write-Host "[..] Launching installer (new window) ..."
Write-Host "     Administrator privileges will be requested if needed."
Start-Process powershell -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-ConfigFile", $confPath
)

Write-Host ""
Write-Host "=== 引导完成 ==="
Write-Host "Installer is running in a separate window."
Write-Host "Check that window for installation progress."
