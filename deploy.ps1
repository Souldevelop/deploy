param(
    [string]$ConfigFile = ""
)

$ScriptVersion = "2.2.8"

# Force TLS 1.2 for WebClient downloading (important for npmmirror CDN)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# ============================================================================
# Helper functions
# ============================================================================

function Write-Step($msg) { Write-Host "[ == ] $msg" }
function Write-OK($msg)   { Write-Host "[ OK ] $msg" }
function Write-Warn($msg) { Write-Host "[WW] $msg" }
function Write-Err($msg)  { Write-Host "[ER] $msg" }

# ============================================================================
# Admin elevation
# ============================================================================

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$id
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Elevate {
    if (-not (Test-Admin)) {
        Write-Step "Requesting administrator privileges..."
        $argList = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $PSCommandPath
        )
        if ($ConfigFile) {
            $argList += '-ConfigFile', $ConfigFile
        }
        Start-Process powershell -Verb RunAs -ArgumentList $argList
        exit
    }
}

# ============================================================================
# Load config
# ============================================================================

function Load-Config($Path) {
    $config = @{}
    if (-not (Test-Path $Path)) {
        Write-Step "No config file found at $Path"
        return $config
    }
    Write-Step "Loading configuration from $Path..."
    Get-Content $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and $line[0] -ne '#') {
            $eq = $line.IndexOf('=')
            if ($eq -gt 0) {
                $key = $line.Substring(0, $eq).Trim()
                $value = $line.Substring($eq + 1).Trim()
                $config[$key] = $value
            }
        }
    }
    Write-OK "Configuration loaded"
    return $config
}

# ============================================================================
# Download helpers with KB/MB progress
# ============================================================================

function Format-FileSize($bytes) {
    if ($bytes -ge 1MB) { return "$([Math]::Round($bytes/1MB, 1)) MB" }
    if ($bytes -ge 1KB) { return "$([Math]::Round($bytes/1KB, 1)) KB" }
    return "$bytes B"
}

function Download-File {
    param([string]$Url, [string]$OutFile)

    # Get file size via HEAD request (for percentage display)
    $totalBytes = 0L
    try {
        $req = [System.Net.WebRequest]::Create($Url)
        $req.Method = 'HEAD'
        $req.Timeout = 5000
        $resp = $req.GetResponse()
        $totalBytes = $resp.ContentLength
        $resp.Close()
    } catch { }

    # Launch download in background (no progress bar overhead)
    $oldPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    $job = Start-Job -ScriptBlock { param($u,$o) $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $u -OutFile $o -UseBasicParsing | Out-Null } -Args $Url,$OutFile

    # Monitor progress by checking file size periodically
    do {
        Start-Sleep -Milliseconds 400
        if ((Test-Path $OutFile) -and $totalBytes -gt 0) {
            $sz = (Get-Item $OutFile).Length
            $pct = [Math]::Round($sz / $totalBytes * 100, 1)
            $pctStr = "$pct%".PadRight(6)
            Write-Host "`r[ .. ] $pctStr" -NoNewline
        }
    } while ($job.State -eq 'Running')

    Receive-Job $job -Wait | Out-Null
    Remove-Job $job
    $ProgressPreference = $oldPref
    Write-Host ""

    if (Test-Path $OutFile) {
        $sz = Format-FileSize ((Get-Item $OutFile).Length)
        Write-OK "Downloaded: $sz"
    }
}

# ============================================================================
# Find Node.js in PATH
# ============================================================================

function Find-NodeJS {
    $exe = Get-Command node -ErrorAction SilentlyContinue
    if ($exe) { return $true }

    $paths = @(
        "$env:ProgramFiles\nodejs",
        "${env:ProgramFiles(x86)}\nodejs",
        "$env:LocalAppData\OpenJS\NodeJS"
    )
    foreach ($p in $paths) {
        if (Test-Path "$p\node.exe") {
            $env:Path = "$p;$env:Path"
            return $true
        }
    }
    return $false
}

# ============================================================================
# Install Node.js
# ============================================================================

function Install-NodeJS {
    # Check existing before showing header
    try { $nodeVer = & node --version 2>$null } catch { $nodeVer = $null }
    if ($nodeVer -and $nodeVer -match 'v(\d+)\.') {
        $major = [int]$Matches[1]
        if ($major -ge 18) {
            Write-Host ""
            Write-OK "Node.js v$major already installed, skipping"
            return $true
        }
    }

    Write-Host ""
    Write-Step "Node.js installation"

    $nodeMajor = if ($config.ContainsKey('NODE_MAJOR')) { $config['NODE_MAJOR'] } else { '22' }
    $versions = @{ '22' = '22.14.0'; '20' = '20.18.0' }
    $nodeFull = $versions[$nodeMajor]

    if (-not $nodeFull) {
        Write-Err "Unsupported Node.js major version: $nodeMajor"
        Write-Host "Download from: https://nodejs.org/dist/latest-v${nodeMajor}.x/"
        pause; exit 1
    }

    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_IDENTIFIER -match 'ARM64') { 'arm64' } elseif ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }

    # Use China mirror if NPM_MIRROR is set to npmmirror
    if ($config.ContainsKey('NPM_MIRROR') -and $config['NPM_MIRROR'] -match 'npmmirror') {
        $url = "https://npmmirror.com/mirrors/node/v$nodeFull/node-v$nodeFull-$arch.msi"
        $mirrorName = "npmmirror"
    } else {
        $url = "https://nodejs.org/dist/v$nodeFull/node-v$nodeFull-$arch.msi"
        $mirrorName = "nodejs.org"
    }
    $tmpFile = "$env:TEMP\node-v$nodeFull-$arch.msi"

    Write-Step "Downloading Node.js v$nodeFull ($arch) from $mirrorName..."
    $downloaded = $false
    try {
        Download-File -Url $url -OutFile $tmpFile
    } catch {
        Write-Warn "Download error, checking file..."
    }
    if ((Test-Path $tmpFile) -and ((Get-Item $tmpFile).Length -gt 1MB)) {
        $downloaded = $true
    } else {
        Write-Warn "Download from $mirrorName failed, trying official nodejs.org..."
        $url = "https://nodejs.org/dist/v$nodeFull/node-v$nodeFull-$arch.msi"
        try {
            Download-File -Url $url -OutFile $tmpFile
        } catch {
            Write-Err "Download failed. Install Node.js manually from nodejs.org"
            pause; exit 1
        }
        if ((Test-Path $tmpFile) -and ((Get-Item $tmpFile).Length -gt 1MB)) {
            $downloaded = $true
        } else {
            Write-Err "Download failed. Install Node.js manually from nodejs.org"
            pause; exit 1
        }
    }

    Write-Step "Installing Node.js v$nodeFull (quiet mode)..."
    $proc = Start-Process msiexec -ArgumentList "/i `"$tmpFile`" /quiet /norestart" -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Warn "MSI install exited with code $($proc.ExitCode)"
    }

    Write-Step "Waiting for installation to complete..."
    $found = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 2
        if ($i -gt 0) { Write-Host "." -NoNewline }
        if (Find-NodeJS) { $found = $true; break }
    }
    Write-Host ""

    if (-not $found) {
        Write-Err "Node.js install did not complete within 120 seconds."
        Write-Warn "Install manually from nodejs.org, then run this script again."
        pause; exit 1
    }

    Write-OK "Node.js v$nodeFull installed"
    Find-NodeJS
    return $true
}

# ============================================================================
# Configure npm mirror
# ============================================================================

function Configure-NpmMirror {
    if ($config.ContainsKey('NPM_MIRROR') -and $config['NPM_MIRROR']) {
        $mirror = $config['NPM_MIRROR']
        Write-Step "Configuring npm mirror..."
        & npm config set registry $mirror 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "npm registry set to $mirror"
        } else {
            Write-Warn "Failed to set npm registry"
        }
    }
}

# ============================================================================
# Install Claude Code CLI
# ============================================================================

function Install-ClaudeCode {
    Write-Host ""
    Write-Step "Claude Code CLI installation"

    if (-not (Find-NodeJS)) {
        Write-Err "Node.js not found. Please install Node.js 18+ first."
        pause; exit 1
    }

    $npmPath = (Get-Command npm -ErrorAction SilentlyContinue).Source
    if (-not $npmPath) {
        Write-Err "npm not found. Check Node.js installation."
        pause; exit 1
    }

    $npmPrefix = & npm config get prefix 2>$null
    if ($npmPrefix) {
        $claudeCmd = "$npmPrefix\claude.cmd"
        $claudeBin = "$npmPrefix\node_modules\.bin"
        if (Test-Path $claudeCmd) {
            $env:Path = "$npmPrefix;$env:Path"
        } elseif (Test-Path "$claudeBin\claude.cmd") {
            $env:Path = "$claudeBin;$env:Path"
        }
    }

    Write-Step "Installing @anthropic-ai/claude-code globally..."
    Write-Step "(Downloads ~15MB from npm, may take a minute)..."

    $attempt = 0
    do {
        $attempt++
        if ($attempt -gt 1) { Write-Step "Retry $attempt/3..." }
        & npm install -g @anthropic-ai/claude-code
        if ($LASTEXITCODE -eq 0) { break }
        if ($attempt -lt 3) { Start-Sleep -Seconds 3 }
    } while ($attempt -lt 3)

    if ($LASTEXITCODE -ne 0) {
        Write-Err "npm install failed after $attempt attempts"
        Write-Err "Check network: npm config get registry"
        Write-Err "Retry: npm install -g @anthropic-ai/claude-code"
        pause; exit 1
    }

    Write-OK "@anthropic-ai/claude-code installed"

    # Verify
    try { $claudeVer = & claude --version 2>$null } catch { $claudeVer = $null }
    if ($claudeVer) {
        Write-OK "Claude Code CLI $claudeVer ready"
    } else {
        Write-Warn "claude command not in PATH"
        if ($npmPrefix -and (Test-Path "$npmPrefix\claude.cmd")) {
            $env:Path = "$npmPrefix;$env:Path"
            Write-OK "Claude Code CLI ready"
        }
    }
}

# ============================================================================
# Install CC-Switch (AI API switcher)
# ============================================================================

function Install-CCSwitch {
    Write-Host ""
    Write-Step "CC-Switch installation"

    $ccDir = "${env:ProgramFiles}\CC-Switch"
    if (Test-Path $ccDir) {
        Write-OK "CC-Switch already installed, skipping"
        return $true
    }

    $downloadUrl = if ($config.ContainsKey('CC_SWITCH_URL')) { $config['CC_SWITCH_URL'] } else { "https://raw.githubusercontent.com/Souldevelop/deploy/master/vendor/CC-Switch-Windows.msi" }
    Write-Step "Downloading CC-Switch from deploy repo..."

    $tmpFile = "$env:TEMP\cc-switch-windows.msi"
    try {
        Download-File -Url $downloadUrl -OutFile $tmpFile
    } catch {
        Write-Err "CC-Switch download failed"
        return $false
    }

    Write-Step "Installing CC-Switch (quiet mode)..."
    $proc = Start-Process msiexec -ArgumentList "/i `"$tmpFile`" /quiet /norestart" -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Warn "MSI install exited with code $($proc.ExitCode)"
    }

    if (Test-Path $ccDir) {
        Write-OK "CC-Switch installed"
    } else {
        Write-Warn "CC-Switch install path not found at $ccDir"
        Write-Warn "You may need to install manually from the GitHub releases page"
    }
}

# ============================================================================
# Write Claude Code settings.json
# ============================================================================

function Write-ClaudeConfig {
    Write-Host ""
    Write-Step "Configuring Claude Code..."

    $apiKey = $config['ANTHROPIC_API_KEY']
    $baseUrl = if ($config.ContainsKey('ANTHROPIC_BASE_URL')) { $config['ANTHROPIC_BASE_URL'] } else { $null }
    $model  = if ($config.ContainsKey('ANTHROPIC_MODEL')) { $config['ANTHROPIC_MODEL'] } else { $null }

    if (-not $apiKey) {
        $apiKey = Read-Host "[ == ]  API Key (sk-ant-...)"
    }
    if (-not $baseUrl) {
        $baseUrl = Read-Host "[ == ]  API Base URL"
        if (-not $baseUrl) { $baseUrl = "https://api.anthropic.com" }
    }
    if (-not $model) {
        Write-Host ""
        Write-Host " Select default model:"
        Write-Host "   1) claude-sonnet-4-6-20250224  (Anthropic, recommended)"
        Write-Host "   2) claude-opus-4-6-20250224    (Anthropic, most capable)"
        Write-Host "   3) claude-haiku-4-5-20251001   (Anthropic, fastest)"
        Write-Host "   4) deepseek-v4-flash           (DeepSeek, fast/cheap)"
        Write-Host "   5) deepseek-v4-pro             (DeepSeek, powerful)"
        Write-Host "   6) Enter custom model name"
        Write-Host "   0) Skip (use claude default)"
        $pick = Read-Host " [ == ]  Choice [0-6]"
        switch ($pick) {
            '1' { $model = 'claude-sonnet-4-6-20250224' }
            '2' { $model = 'claude-opus-4-6-20250224' }
            '3' { $model = 'claude-haiku-4-5-20251001' }
            '4' { $model = 'deepseek-v4-flash' }
            '5' { $model = 'deepseek-v4-pro' }
            '6' { $model = Read-Host " [ == ]  Model name" }
        }
    }

    if (-not $model) { $model = "claude-sonnet-4-6-20250224" }
    if (-not $baseUrl) { $baseUrl = "https://api.anthropic.com" }

    $claudeDir = "$env:USERPROFILE\.claude"
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }

    $settings = @{
        env = @{
            ANTHROPIC_AUTH_TOKEN          = $apiKey
            ANTHROPIC_API_KEY             = $apiKey
            ANTHROPIC_BASE_URL            = $baseUrl
            ANTHROPIC_MODEL               = $model
            ANTHROPIC_DEFAULT_HAIKU_MODEL = $model
            ANTHROPIC_DEFAULT_SONNET_MODEL = $model
            ANTHROPIC_DEFAULT_OPUS_MODEL  = $model
            ANTHROPIC_REASONING_MODEL     = $model
        }
    }

    $cfgFile = Join-Path $claudeDir "settings.json"
    $settings | ConvertTo-Json -Depth 3 | Set-Content $cfgFile -Encoding UTF8

    if (Test-Path $cfgFile) {
        Write-OK "Config written to $cfgFile"
        Get-Content $cfgFile | Write-Host
    } else {
        Write-Err "Failed to write config"
    }

    # Connectivity test
    if ($baseUrl) {
        Write-Step "Verifying API endpoint: $baseUrl..."
        try {
            $req = [System.Net.WebRequest]::Create($baseUrl)
            $req.Timeout = 5000
            $req.GetResponse() | Out-Null
            Write-OK "API endpoint reachable"
        } catch {
            Write-Warn "Cannot reach $baseUrl"
            Write-Warn "Check: firewall, DNS, proxy settings"
        }
    }

    Write-OK "Claude Code configuration complete"
}

# ============================================================================
# Print summary
# ============================================================================

function Print-Summary {
    Write-Host ""
    Write-Host ("=" * 50)
    Write-Host "         Deployment Complete"
    Write-Host ("=" * 50)
    Write-Host ""
    Write-Host " Script version: $ScriptVersion"
    try { $nv = & node --version 2>$null } catch { $nv = $null }
    if ($nv) { Write-Host " Node.js:   $nv" }
    try { $npmv = & npm --version 2>$null } catch { $npmv = $null }
    if ($npmv) { Write-Host " npm:       $npmv" }
    try { $cv = & claude --version 2>$null } catch { $cv = $null }
    if ($cv) { Write-Host " Claude:    $cv" }
    Write-Host ""
    Write-Host " Config:    $env:USERPROFILE\.claude\settings.json"
    $ccExe = "${env:ProgramFiles}\CC-Switch\CC-Switch.exe"
    if (Test-Path $ccExe) {
        try { $ccVer = & $ccExe --version 2>$null } catch { $ccVer = $null }
        if ($ccVer) { Write-Host " CC-Switch: $ccVer" }
        else { Write-Host " CC-Switch: installed" }
    }
    Write-Host ""
    Write-Host " Next step: run  claude"
    Write-Host ""
}

# ============================================================================
# Cleanup temp files
# ============================================================================

function Cleanup-TempFiles {
    Write-Host ""
    Write-Step "Cleaning up temporary files..."
    $cleaned = $false
    Get-ChildItem "$env:TEMP\node-*.msi" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        $cleaned = $true
    }
    Get-ChildItem "$env:TEMP\cc-switch*.msi" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        $cleaned = $true
    }
    if ($cleaned) { Write-OK "Temp files cleaned" }
    else { Write-Host "[ .. ] Nothing to clean" }
}

# ============================================================================
# Script config path — resolve BEFORE elevation so path is absolute
# ============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ConfigFile) {
    $ConfigFile = Join-Path $scriptDir "deploy.conf"
} elseif (-not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile = Join-Path $scriptDir $ConfigFile
}

# ============================================================================
# Main
# ============================================================================

Clear-Host
Write-Host ("=" * 50)
Write-Host "   Claude Code CLI + CC-Switch  v2.2.8  2026-05-08"
Write-Host ""
Write-Host "   Developer: ReverseKing   QQ: 441673604"
Write-Host ("=" * 50)
Write-Host ""

Elevate
$config = Load-Config $ConfigFile
Install-NodeJS
Configure-NpmMirror
Install-ClaudeCode
Install-CCSwitch
Write-ClaudeConfig
Cleanup-TempFiles
Print-Summary

pause
