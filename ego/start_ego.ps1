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
            return $command.Path
        }
    }

    foreach ($candidate in $CandidatePaths) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    Write-Host "[EGO] $FriendlyName 실행 파일을 찾지 못했습니다." -ForegroundColor Yellow
    if ($InstallHint) {
        Write-Host "        설치 힌트: $InstallHint"
    }
    throw "필수 실행 파일($FriendlyName)이 없어서 MIRROR STAGE EGO를 시작할 수 없습니다."
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

if (-not (Test-Path $backendDir)) {
    throw "백엔드 디렉터리를 찾을 수 없습니다: $backendDir"
}
if (-not (Test-Path $frontendDir)) {
    throw "프런트엔드 디렉터리를 찾을 수 없습니다: $frontendDir"
}

$npmPath = $null
if (-not $FrontendOnly) {
    $npmCandidates = @(
        "$env:LOCALAPPDATA\Programs\nodejs\npm.cmd",
        "C:\Program Files\nodejs\npm.cmd",
        "C:\Program Files (x86)\nodejs\npm.cmd"
    )
    $npmPath = Resolve-Executable -CommandNames @("npm.cmd","npm") -CandidatePaths $npmCandidates -FriendlyName "npm" -InstallHint "https://nodejs.org에서 Node.js 20.x LTS 설치"
}

$flutterPath = $null
if (-not $BackendOnly) {
    $flutterCandidates = @(
        "C:\Program Files\Google\Flutter\bin\flutter.bat",
        "C:\Program Files (x86)\Google\Flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\Programs\Flutter\bin\flutter.bat"
    )
    $flutterPath = Resolve-Executable -CommandNames @("flutter.bat","flutter") -CandidatePaths $flutterCandidates -FriendlyName "Flutter" -InstallHint "winget install Google.Flutter 후 PowerShell 재시작"
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
Write-Host "[EGO] 상태 확인을 위해 이 창을 유지합니다. 종료하려면 Enter 키를 누르세요." -ForegroundColor Yellow
try {
    Read-Host | Out-Null
} catch {
    # ignore when host is non-interactive
}
