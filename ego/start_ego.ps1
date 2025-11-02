Param(
    [switch]$FrontendOnly,
    [switch]$BackendOnly
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $root "backend"
$frontendDir = Join-Path $root "frontend"

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
            return @{ Path = $command.Path; Error = $null }
        }
    }

    foreach ($candidate in $CandidatePaths) {
        if (Test-Path $candidate) {
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
        "C:\Program Files (x86)\nodejs\npm.cmd"
    )
    $npmResolution = Resolve-Executable -CommandNames @("npm.cmd","npm") -CandidatePaths $npmCandidates -FriendlyName "npm" -InstallHint "https://nodejs.org에서 Node.js 20.x LTS 설치"
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
        "$env:LOCALAPPDATA\Programs\Flutter\bin\flutter.bat"
    )
    $flutterResolution = Resolve-Executable -CommandNames @("flutter.bat","flutter") -CandidatePaths $flutterCandidates -FriendlyName "Flutter" -InstallHint "winget install Google.Flutter 후 PowerShell 재시작"
    $flutterPath = $flutterResolution.Path
    if (-not $flutterPath) {
        $errors += $flutterResolution.Error
    }
}

if ($errors.Count -gt 0) {
    Write-Host "MIRROR STAGE EGO를 시작할 수 없습니다." -ForegroundColor Red
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    Write-Host "필요한 구성 요소를 설치/수정한 뒤 다시 시도해 주세요." -ForegroundColor Yellow
    Read-Host -Prompt "[EGO] Enter 키를 누르면 창이 닫힙니다"
    exit 1
}

if (-not $FrontendOnly) {
    $npmCommand = '"' + $npmPath + '" run start:dev'
    Start-CmdWindow -WorkingDirectory $backendDir -CommandLine $npmCommand -Title "MIRROR STAGE EGO Backend"
    Write-Host "[EGO] 백엔드를 시작했습니다. 창이 뜨기까지 잠시 기다려 주세요." -ForegroundColor Green
}

if (-not $BackendOnly) {
    $flutterCommand = '"' + $flutterPath + '" run -d edge --web-hostname=0.0.0.0 --web-port=8080 --dart-define=MIRROR_STAGE_WS_URL=http://10.0.0.100:3000/digital-twin'
    Start-CmdWindow -WorkingDirectory $frontendDir -CommandLine $flutterCommand -Title "MIRROR STAGE EGO Frontend"
    Write-Host "[EGO] 프런트엔드를 시작했습니다. Edge 브라우저가 자동으로 열립니다." -ForegroundColor Green
}

Write-Host "[EGO] 두 창을 닫으면 서비스가 중지됩니다." -ForegroundColor Green
Read-Host -Prompt "[EGO] 상태 창을 종료하려면 Enter 키를 누르세요"
