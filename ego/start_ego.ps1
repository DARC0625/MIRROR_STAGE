Param(
    [switch]$FrontendOnly,
    [switch]$BackendOnly
)

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
            Write-Log "[EGO] $FriendlyName 경로 탐지: $($command.Path)" ([ConsoleColor]::DarkGray)
            return @{ Path = $command.Path; Error = $null }
        }
    }

    foreach ($candidate in $CandidatePaths) {
        if (Test-Path $candidate) {
            Write-Log "[EGO] $FriendlyName 경로 후보 사용: $candidate" ([ConsoleColor]::DarkGray)
            return @{ Path = $candidate; Error = $null }
        }
    }

    $message = "[EGO] $FriendlyName 실행 파일을 찾지 못했습니다."
    if ($InstallHint) {
        $message += " `n        설치 힌트: $InstallHint"
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
    Write-Log "[EGO] 창 실행: $arguments" ([ConsoleColor]::DarkGray)
    Start-Process -FilePath $env:ComSpec -ArgumentList $arguments
}

$errors = @()

if (-not (Test-Path $backendDir)) {
    $errors += "[EGO] 백엔드 디렉터리를 찾을 수 없습니다: $backendDir"
}
if (-not (Test-Path $frontendDir)) {
    $errors += "[EGO] 프런트엔드 디렉터리를 찾을 수 없습니다: $frontendDir"
}

$npmPath = $null
if (-not $FrontendOnly) {
    $npmCandidates = @(
        "$env:LOCALAPPDATA\Programs\nodejs\npm.cmd",
        "C:\Program Files\nodejs\npm.cmd",
        "C:\Program Files (x86)\nodejs\npm.cmd",
        "C:\Program Files\nodejs\node_modules\npm\bin\npm.cmd"
    )
    $npmResolution = Resolve-Executable -CommandNames @("npm.cmd","npm") -CandidatePaths $npmCandidates -FriendlyName "npm" -InstallHint "https://nodejs.org 에서 Node.js 20.x LTS 설치 후 새 창에서 다시 실행"
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
    $flutterResolution = Resolve-Executable -CommandNames @("flutter.bat","flutter") -CandidatePaths $flutterCandidates -FriendlyName "Flutter" -InstallHint "winget install Google.Flutter 실행 후 Windows 로그아웃/재로그인"
    $flutterPath = $flutterResolution.Path
    if (-not $flutterPath) {
        $errors += $flutterResolution.Error
    }
}

if ($errors.Count -gt 0) {
    Write-Log "MIRROR STAGE EGO를 시작할 수 없습니다." ([ConsoleColor]::Red)
    foreach ($err in $errors) {
        Write-Log $err ([ConsoleColor]::Yellow)
    }
    Write-Log "필요한 구성 요소를 설치/수정한 뒤 다시 시도해 주세요." ([ConsoleColor]::Yellow)
    try {
        Read-Host -Prompt "[EGO] Enter 키를 누르면 창이 닫힙니다" | Out-Null
    } catch {
        Start-Sleep -Seconds 5
    }
    exit 1
}

if (-not $FrontendOnly) {
    $npmCommand = '"' + $npmPath + '" run start:dev'
    Start-CmdWindow -WorkingDirectory $backendDir -CommandLine $npmCommand -Title "MIRROR STAGE EGO Backend"
    Write-Log "[EGO] 백엔드를 시작했습니다. 창이 뜨기까지 잠시 기다려 주세요." ([ConsoleColor]::Green)
}

if (-not $BackendOnly) {
    $flutterCommand = '"' + $flutterPath + '" run -d edge --web-hostname=0.0.0.0 --web-port=8080 --dart-define=MIRROR_STAGE_WS_URL=http://10.0.0.100:3000/digital-twin'
    Start-CmdWindow -WorkingDirectory $frontendDir -CommandLine $flutterCommand -Title "MIRROR STAGE EGO Frontend"
    Write-Log "[EGO] 프런트엔드를 시작했습니다. Edge 브라우저가 자동으로 열립니다." ([ConsoleColor]::Green)
}

Write-Log "[EGO] 두 창을 닫으면 서비스가 중지됩니다." ([ConsoleColor]::Green)
try {
    Read-Host -Prompt "[EGO] 상태 창을 종료하려면 Enter 키를 누르세요" | Out-Null
} catch {
    Start-Sleep -Seconds 5
}
