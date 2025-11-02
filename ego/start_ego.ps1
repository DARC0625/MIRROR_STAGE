Param(
    [switch]$FrontendOnly,
    [switch]$BackendOnly
)

$encodingApplied = $false
try {
    chcp 65001 > $null
    $OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
    $encodingApplied = $true
} catch {
    # Swallow errors when chcp fails (non-interactive host etc.)
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $root "backend"
$frontendDir = Join-Path $root "frontend"
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
        # host may not support colors (e.g., executed without console)
        Write-Host $Message
    }
}

if ($encodingApplied) {
    Write-Log "[EGO] Console encoding switched to UTF-8." ([ConsoleColor]::DarkGray)
}

function Resolve-Executable {
    param(
        [string[]]$CommandNames,
        [string[]]$CandidatePaths,
        [string]$FriendlyName,
        [string]$InstallHint
    )

    foreach ($name in $CommandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            Write-Log "[EGO] Detected $FriendlyName at $($command.Path)" ([ConsoleColor]::DarkGray)
            return @{ Path = $command.Path; Error = $null }
        }
    }

    foreach ($candidate in $CandidatePaths) {
        if (Test-Path $candidate) {
            Write-Log "[EGO] Using candidate path for $FriendlyName: $candidate" ([ConsoleColor]::DarkGray)
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

$errors = @()

if (-not (Test-Path $backendDir)) {
    $errors += "[EGO] Backend directory was not found: $backendDir"
}
if (-not (Test-Path $frontendDir)) {
    $errors += "[EGO] Frontend directory was not found: $frontendDir"
}

$npmPath = $null
if (-not $FrontendOnly) {
    $npmCandidates = @(
        "$env:LOCALAPPDATA\Programs\nodejs\npm.cmd",
        "C:\Program Files\nodejs\npm.cmd",
        "C:\Program Files (x86)\nodejs\npm.cmd",
        "C:\Program Files\nodejs\node_modules\npm\bin\npm.cmd"
    )
    $npmResolution = Resolve-Executable -CommandNames @("npm.cmd","npm") -CandidatePaths $npmCandidates -FriendlyName "npm" -InstallHint "Install Node.js 20.x LTS from https://nodejs.org, then reopen this launcher"
    $npmPath = $npmResolution.Path
    if (-not $npmPath) {
        $errors += $npmResolution.Error
    }
}

$flutterPath = $null
if (-not $BackendOnly) {
    $flutterCandidates = @(
        "C:\Program Files\Google\Flutter\bin\flutter.bat",
        "C:\Program Files (x86)\Google\Flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\Programs\Flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\Programs\Flutter\flutter\bin\flutter.bat",
        "C:\src\flutter\bin\flutter.bat"
    )
    $flutterResolution = Resolve-Executable -CommandNames @("flutter.bat","flutter") -CandidatePaths $flutterCandidates -FriendlyName "Flutter" -InstallHint "Run `winget install Google.Flutter`, then sign out and sign back in to Windows"
    $flutterPath = $flutterResolution.Path
    if (-not $flutterPath) {
        $errors += $flutterResolution.Error
    }
}

if ($errors.Count -gt 0) {
    Write-Log "[EGO] Unable to start MIRROR STAGE EGO." ([ConsoleColor]::Red)
    foreach ($err in $errors) {
        Write-Log $err ([ConsoleColor]::Yellow)
    }
    Write-Log "[EGO] Please install or configure the required components and try again." ([ConsoleColor]::Yellow)
    try {
        Read-Host -Prompt "[EGO] Press Enter to close this window" | Out-Null
    } catch {
        Start-Sleep -Seconds 5
    }
    exit 1
}

if (-not $FrontendOnly) {
    $npmCommand = '"' + $npmPath + '" run start:dev'
    Start-CmdWindow -WorkingDirectory $backendDir -CommandLine $npmCommand -Title "MIRROR STAGE EGO Backend"
    Write-Log "[EGO] Backend process started. Please wait for the NestJS window to appear." ([ConsoleColor]::Green)
}

if (-not $BackendOnly) {
    $flutterCommand = '"' + $flutterPath + '" run -d edge --web-hostname=0.0.0.0 --web-port=8080 --dart-define=MIRROR_STAGE_WS_URL=http://10.0.0.100:3000/digital-twin'
    Start-CmdWindow -WorkingDirectory $frontendDir -CommandLine $flutterCommand -Title "MIRROR STAGE EGO Frontend"
    Write-Log "[EGO] Frontend process started. An Edge window will open automatically." ([ConsoleColor]::Green)
}

Write-Log "[EGO] Close the backend/frontend consoles to stop the services." ([ConsoleColor]::Green)
try {
    Read-Host -Prompt "[EGO] Press Enter to close this status window" | Out-Null
} catch {
    Start-Sleep -Seconds 5
}
