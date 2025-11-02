Param(
    [switch]$FrontendOnly,
    [switch]$BackendOnly
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $root "backend"
$frontendDir = Join-Path $root "frontend"

function Ensure-Command {
    param(
        [string]$CommandName,
        [string]$InstallHint
    )

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        Write-Host "[EGO] '$CommandName' 을(를) 찾을 수 없습니다." -ForegroundColor Yellow
        if ($InstallHint) {
            Write-Host "        설치 힌트: $InstallHint"
        }
        throw "필수 명령 '$CommandName' 이(가) PATH 에 없습니다."
    }
}

if (-not $FrontendOnly) {
    Ensure-Command -CommandName "npm" -InstallHint "https://nodejs.org에서 Node.js 20.x LTS 설치"
}
if (-not $BackendOnly) {
    Ensure-Command -CommandName "flutter" -InstallHint "flutter doctor 실행 후 PATH에 Flutter SDK 추가"
}

function Start-CmdWindow {
    param(
        [string]$WorkingDirectory,
        [string]$CommandLine,
        [string]$Title
    )

    $cmd = 'cmd.exe'
    $args = "/K title $Title && cd /d `"$WorkingDirectory`" && $CommandLine"
    Start-Process -FilePath $cmd -ArgumentList $args
}

if (-not $FrontendOnly) {
    if (-not (Test-Path $backendDir)) {
        throw "백엔드 디렉터리를 찾을 수 없습니다: $backendDir"
    }
    Start-CmdWindow -WorkingDirectory $backendDir -CommandLine "npm run start:dev" -Title "MIRROR STAGE EGO Backend"
}

if (-not $BackendOnly) {
    if (-not (Test-Path $frontendDir)) {
        throw "프런트엔드 디렉터리를 찾을 수 없습니다: $frontendDir"
    }
    $flutterCommand = 'flutter run -d edge --web-hostname=0.0.0.0 --web-port=8080 --dart-define=MIRROR_STAGE_WS_URL=http://10.0.0.100:3000/digital-twin'
    Start-CmdWindow -WorkingDirectory $frontendDir -CommandLine $flutterCommand -Title "MIRROR STAGE EGO Frontend"
}

Write-Host "[EGO] 새 창에서 백엔드/프런트엔드가 실행됩니다. 종료하려면 각 창을 닫으세요." -ForegroundColor Green
