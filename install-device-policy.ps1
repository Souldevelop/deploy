<#
.SYNOPSIS
    Claude Code Device Policy Installer for Windows
.DESCRIPTION
    Injects device management skill, operation logging, and permission config
    into Claude Code for Windows 10/11. Zero external dependencies.

    Remote execution:
        Gitee:
            powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object Net.WebClient).DownloadString('https://gitee.com/reverseking/deploy/raw/master/install-device-policy.ps1'))"
        GitHub:
            powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/Souldevelop/deploy/master/install-device-policy.ps1'))"
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Claude Code Device Policy Installer (Windows) ==="
Write-Host ""

# ====================================================================
# Collect device information
# ====================================================================
Write-Host " - Collecting device information..."

$hostname = hostname
$arch = $env:PROCESSOR_ARCHITECTURE
try {
    $osInfo = (Get-CimInstance Win32_OperatingSystem).Caption
    $kernel = (Get-CimInstance Win32_OperatingSystem).Version
    # Win32_Processor may return multiple instances on hybrid CPU (P-core+E-core)
    $cpuList = Get-CimInstance Win32_Processor
    $cpuModel = $cpuList | Select-Object -First 1 -ExpandProperty Name
    $cpuCores = ($cpuList | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $cpuMaxMHz = $cpuList | Select-Object -First 1 -ExpandProperty MaxClockSpeed
    $memBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $memTotal = [math]::Round($memBytes / 1GB, 1)
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Where-Object DeviceID -eq "C:"
    if ($disk) {
        $diskTotal = [math]::Round($disk.Size / 1GB, 1)
        $diskFree  = [math]::Round($disk.FreeSpace / 1GB, 1)
        $diskUsed  = $diskTotal - $diskFree
    } else { $diskTotal = "?"; $diskUsed = "?" }
    $ipAddr = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -ne 'Loopback').IPAddress -join ' '
    $deviceModel = (Get-CimInstance Win32_ComputerSystem).Model
    if (-not $deviceModel -or $deviceModel -match "System Product|To Be Filled|O\.E\.M\.") {
        $deviceModel = "$arch PC"
    }
    Write-Host " [+] $deviceModel"
    Write-Host " [+] $osInfo"
    Write-Host " [+] $cpuModel ($cpuCores cores)"
} catch {
    Write-Host " [x] Device info collection failed: $($_.Exception.Message)"
    $deviceModel = "$arch PC"
    $osInfo = "$([Environment]::OSVersion)"
    $cpuModel = "?"; $cpuCores = "?"; $cpuMaxMHz = "?"
    $memTotal = "?"; $diskTotal = "?"; $diskUsed = "?"
    $ipAddr = "?"
}
Write-Host ""

# ====================================================================
# Default duties
# ====================================================================
$adminDuties = @"
- 系统监控（CPU、内存、磁盘、网络）
- 软件维护（更新、包管理）
- 网络管理
- 故障排查
- 安全管理
"@

# ====================================================================
# Directory creation
# ====================================================================
$claudeDir   = "$env:USERPROFILE\.claude"
$policyDir   = "$claudeDir\device-policy"
$logDir      = "$policyDir\logs"
$memoryDir   = "$claudeDir\projects\-root\memory"
New-Item -ItemType Directory -Path $policyDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $memoryDir -Force | Out-Null

# ====================================================================
# SKILL.md
# ====================================================================
@"
---
name: device-policy
description: |
  Device administration skill for $deviceModel ($hostname).
  TRIGGER WHEN the user mentions: "设备", "device", "管理", "维护", "maintenance",
  "监控", "性能", "performance", "network", "系统状态", "update", "升级",
  "备份", "配置", "config", or any system administration task on this device.
---

# Device Administration -- $deviceModel

You are the **primary system administrator** for this device.

## Device Identity

| Attribute | Value |
|-----------|-------|
| **Model** | $deviceModel |
| **Hostname** | $hostname |
| **OS** | $osInfo |
| **Kernel** | $kernel ($arch) |

## Hardware

- **CPU**: $cpuModel, $cpuCores cores @ $cpuMaxMHz MHz
- **RAM**: ${memTotal} GB
- **Disk**: ${diskUsed} GB used / ${diskTotal} GB total
- **Network**: $ipAddr

## Responsibilities

$adminDuties

## Rules

1. **Session-start**: Device context auto-loaded via SessionStart hook.
2. **Permissions**: All tool operations auto-approved (settings.local.json).
3. **Logging**: Modifications logged to ~/.claude/device-policy/logs/.
4. **Safety**: Dangerous operations (rm -rf /, dd) blocked.

## Quick Reference

\`\`\`powershell
Get-Process                     # Process listing
Get-CimInstance Win32_LogicalDisk  # Disk info
ipconfig /all                   # Network config
Get-NetTCPConnection            # Ports
\`\`\`
"@ | Set-Content "$policyDir\SKILL.md" -Encoding UTF8
Write-Host " [+] SKILL.md"

# ====================================================================
# device-context-hook.ps1 -- SessionStart hook
# ====================================================================
@'
#!/usr/bin/env pwsh
# device-context-hook.ps1 -- SessionStart hook for device-policy
$skillPath = Join-Path $env:USERPROFILE ".claude" "device-policy" "SKILL.md"
if (-not (Test-Path $skillPath)) {
    Write-Output '{"systemMessage":"Device policy skill not found"}'
    exit 0
}
$content = Get-Content $skillPath -Raw
$obj = @{
    hookSpecificOutput = @{
        hookEventName = "SessionStart"
        additionalContext = $content
    }
}
$obj | ConvertTo-Json -Compress -Depth 3
'@ | Set-Content "$policyDir\device-context-hook.ps1" -Encoding UTF8
Write-Host " [+] device-context-hook.ps1"

# ====================================================================
# device-log-hook.ps1 -- PreToolUse hook
# ====================================================================
@'
#!/usr/bin/env pwsh
# device-log-hook.ps1 -- PreToolUse hook for device-policy
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrEmpty($raw)) { exit 0 }
try { $inputObj = $raw | ConvertFrom-Json } catch { exit 0 }
if (-not $inputObj -or -not $inputObj.tool_name) { exit 0 }

$toolName = $inputObj.tool_name
$timestamp = Get-Date -Format "HH:mm:ss"
$logDate = Get-Date -Format "yyyyMMdd"
$sessionLog = Join-Path $env:USERPROFILE ".claude" "device-policy" "logs" "$logDate.md"

if (-not (Test-Path $sessionLog)) {
    "# Session $(Get-Date -Format 'yyyy-MM-dd HH:mm') - Device Operations Log" | Set-Content $sessionLog
}

# Filter read-only Bash commands
if ($toolName -eq "Bash" -and $inputObj.command) {
    $cmd = $inputObj.command
    $ro = @(
        '^ls\b','^cat\s+/proc','^head\s+','^tail\s+','^echo\s+','^grep\s+',
        '^find\s+','^which\s+','^who\b','^uptime\b','^free\b','^df\b','^ps\b',
        '^ss\b','^date\b','^pwd\b','^id\b','^uname\b','^hostname\b',
        '^history\b','^printenv\b','^git\s+(status|log|diff|--version)\b',
        '^npm\b','^docker\s+ps\b','^systemctl\s+(status|list-)\b','^journalctl\b'
    )
    foreach ($p in $ro) { if ($cmd -match $p) { exit 0 } }
}

# Skip log/memory file ops
if ($toolName -in @('Write','Edit') -and $inputObj.file_path) {
    $fp = $inputObj.file_path
    if ($fp -match 'device-policy\\logs\\' -or $fp -match '\\.claude\\memory\\') { exit 0 }
}

$entry = "`n## $timestamp - $toolName`n``````n$raw`n``````"
Add-Content $sessionLog $entry
'@ | Set-Content "$policyDir\device-log-hook.ps1" -Encoding UTF8
Write-Host " [+] device-log-hook.ps1"

# ====================================================================
# settings.local.json
# ====================================================================
$ctxHookPath = Join-Path $policyDir "device-context-hook.ps1"
$logHookPath = Join-Path $policyDir "device-log-hook.ps1"
$ctxCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ctxHookPath`""
$logCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$logHookPath`" 2`$null"

$settings = @{
    permissions = @{
        allow = @("Bash", "Read", "Write", "Edit", "WebSearch", "WebFetch", "Glob", "Grep")
        deny  = @("Bash(rm -rf /)", "Bash(rm -rf /*)", "Bash(> /dev/sd*)", "Bash(dd if=/dev/zero)")
    }
    hooks = @{
        SessionStart = @(
            @{
                hooks = @(
                    @{
                        type    = "command"
                        command = $ctxCmd
                        timeout = 5
                        statusMessage = "Loading device policy context..."
                    }
                )
            }
        )
        PreToolUse = @(
            @{
                matcher = "Bash|Write|Edit"
                hooks = @(
                    @{
                        type    = "command"
                        command = $logCmd
                        timeout = 5
                        statusMessage = ""
                    }
                )
            }
        )
    }
}
$settings | ConvertTo-Json -Depth 5 | Set-Content "$claudeDir\settings.local.json" -Encoding UTF8
Write-Host " [+] settings.local.json"

# ====================================================================
# Memory files
# ====================================================================
@"
- [Device Admin](device_admin.md) -- Device specs, admin responsibilities, and management rules
"@ | Set-Content "$memoryDir\MEMORY.md" -Encoding UTF8

@"
---
name: Device Administration
description: Device admin info -- loaded via SessionStart hook and settings.local.json
type: reference
---

**Device**: $deviceModel ($hostname)
**OS**: $osInfo
**Admin rules**: SessionStart hook injects skill context; PreToolUse hook logs operations; permissions auto-approved.
"@ | Set-Content "$memoryDir\device_admin.md" -Encoding UTF8
Write-Host " [+] memory files"

# ====================================================================
# Summary
# ====================================================================
Write-Host ""
Write-Host "=== Deployment Complete ==="
Write-Host ""
Write-Host "  $policyDir\SKILL.md"
Write-Host "  $policyDir\device-context-hook.ps1"
Write-Host "  $policyDir\device-log-hook.ps1"
Write-Host "  $policyDir\logs\"
Write-Host "  $claudeDir\settings.local.json"
Write-Host ""
Write-Host "New session auto-load:"
Write-Host "  1. SessionStart -> auto-load device profile"
Write-Host "  2. Permissions auto-approved"
Write-Host "  3. Operations auto-logged"
Write-Host ""
