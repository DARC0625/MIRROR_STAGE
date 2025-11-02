Param(
    [switch]$SkipBrowserLaunch,
    [int]$Port = 3000
)

$encodingApplied = $false
try {
    chcp 65001 > $null
    $OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
    $encodingApplied = $true
} catch {
    # Host may not allow changing code page (e.g. running from Task Scheduler)
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = Split-Path -Parent $root
$toolsDir = Join-Path $installRoot "tools"
$backendDir = Join-Path $root "backend"
$backendEntry = Join-Path $backendDir "dist\main.js"
$logDir = Join-Path $root "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir ("launcher-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".log")

function Write-Log {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $line
    try {
        Write-Host $Message -ForegroundColor $Color
    } catch {
        Write-Host $Message
    }
}

if ($encodingApplied) {
    Write-Log "[EGO] Console encoding switched to UTF-8." ([ConsoleColor]::DarkGray)
}

function Resolve-Binary {
    param(
        [string[]]$CommandNames,
        [string[]]$CandidatePaths,
        [string]$FriendlyName,
        [string]$InstallHint
    )

    foreach ($name in $CommandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            Write-Log "[EGO] Detected ${FriendlyName} at $($command.Path)" ([ConsoleColor]::DarkGray)
            return @{ Path = $command.Path; Error = $null }
        }
    }

    foreach ($candidate in $CandidatePaths) {
        if (Test-Path $candidate) {
            Write-Log "[EGO] Using candidate path for ${FriendlyName}: $candidate" ([ConsoleColor]::DarkGray)
            return @{ Path = $candidate; Error = $null }
        }
    }

    $message = "[EGO] Could not find $FriendlyName executable."
    if ($InstallHint) {
        $message += " `n        Hint: $InstallHint"
    }
    return @{ Path = $null; Error = $message }
}

function Start-CmdWindow {
    param(
        [string]$WorkingDirectory,
        [string]$CommandLine,
        [string]$Title
    )

    $arguments = "/K title $Title && cd /d `"$WorkingDirectory`" && $CommandLine"
    Write-Log "[EGO] Launching console: $arguments" ([ConsoleColor]::DarkGray)
    Start-Process -FilePath $env:ComSpec -ArgumentList $arguments
}

if (-not (Test-Path $backendDir)) {
    Write-Log "[EGO] Backend directory was not found: $backendDir" ([ConsoleColor]::Yellow)
}
if (-not (Test-Path $backendEntry)) {
    Write-Log "[EGO] Backend build artifacts are missing ($backendEntry)." ([ConsoleColor]::Yellow)
}

$nodeCandidates = @(
    (Join-Path $toolsDir "node\node.exe"),
    (Join-Path $toolsDir "node\bin\node.exe"),
    "C:\Program Files\nodejs\node.exe",
    "C:\Program Files (x86)\nodejs\node.exe",
    "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
    "$env:ProgramFiles\nodejs\node.exe"
)
$node = Resolve-Binary -CommandNames @("node.exe","node") -CandidatePaths $nodeCandidates -FriendlyName "Node.js" -InstallHint "Reinstall MIRROR STAGE or install Node.js 20+ from https://nodejs.org/en/download"

$errors = @()
if (-not (Test-Path $backendDir)) {
    $errors += "[EGO] Backend files are missing. Re-run the installer."
}
if (-not (Test-Path $backendEntry)) {
    $errors += "[EGO] Build output not found at $backendEntry. Run `.\install-mirror-stage-ego.ps1` with administrator privileges."
}
if (-not $node.Path) {
    $errors += $node.Error
}

if ($errors.Count -gt 0) {
    Write-Log "[EGO] Unable to start MIRROR STAGE EGO." ([ConsoleColor]::Red)
    foreach ($err in $errors) {
        Write-Log $err ([ConsoleColor]::Yellow)
    }
    Write-Log "[EGO] Please resolve the issues above and restart." ([ConsoleColor]::Yellow)
    try {
        Read-Host -Prompt "[EGO] Press Enter to close this window" | Out-Null
    } catch {
        Start-Sleep -Seconds 5
    }
    exit 1
}

$nodeCommand = '"' + $node.Path + '" "' + $backendEntry + '"'
Start-CmdWindow -WorkingDirectory $backendDir -CommandLine $nodeCommand -Title "MIRROR STAGE EGO Backend"
Write-Log "[EGO] Backend process started. Waiting for health check on port $Port..." ([ConsoleColor]::Green)

$healthUrl = "http://localhost:$Port/api/health"
$healthCheckPassed = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 3
        if ($response.StatusCode -eq 200) {
            $healthCheckPassed = $true
            break
        }
    } catch {
        Start-Sleep -Seconds 2
    }
}

if ($healthCheckPassed) {
    Write-Log "[EGO] Backend is online at http://localhost:$Port" ([ConsoleColor]::Green)
    if (-not $SkipBrowserLaunch) {
        Write-Log "[EGO] Opening dashboard in your default browser..." ([ConsoleColor]::Green)
        Start-Process "http://localhost:$Port"
    } else {
        Write-Log "[EGO] Browser launch skipped. Open http://localhost:$Port manually." ([ConsoleColor]::Yellow)
    }
} else {
    Write-Log "[EGO] Backend failed to respond. Review the backend console window for errors." ([ConsoleColor]::Red)
}

Write-Log "[EGO] Close the backend console window to stop the services." ([ConsoleColor]::Green)
try {
    Read-Host -Prompt "[EGO] Press Enter to close this status window" | Out-Null
} catch {
    Start-Sleep -Seconds 5
}
