Param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\MIRROR_STAGE_REFLECTOR"
)

$ErrorActionPreference = 'Stop'
$bundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceReflector = Join-Path $bundleRoot 'reflector'
if (-not (Test-Path $sourceReflector)) {
    throw "Reflector sources not found in bundle."
}

function Write-Info($msg) {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $msg"
}

function Ensure-Directories {
    if (-not (Test-Path $InstallRoot)) {
        New-Item -ItemType Directory -Path $InstallRoot | Out-Null
    }
}

function Resolve-Python {
    $candidates = @('py -3','py','python3','python')
    foreach ($cmd in $candidates) {
        try {
            $process = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmd --version" -NoNewWindow -PassThru -Wait -ErrorAction SilentlyContinue
            if ($process.ExitCode -eq 0) {
                if ($cmd.StartsWith('py')) {
                    return $cmd
                }
                return $cmd
            }
        } catch {
            continue
        }
    }
    throw "Python 3.x 실행 파일을 찾지 못했습니다. Microsoft Store 또는 python.org에서 Python 3을 설치한 뒤 다시 시도하세요."
}

function Invoke-Python($pythonCmd, $arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.Arguments = "/c $pythonCmd $arguments"
    $psi.WorkingDirectory = $InstallRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::Start($psi)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Python 명령 실행 실패: $arguments"
    }
}

Ensure-Directories

Write-Info "설치 디렉터리: $InstallRoot"
if (Test-Path (Join-Path $InstallRoot 'reflector')) {
    Remove-Item -Path (Join-Path $InstallRoot 'reflector') -Recurse -Force
}
Copy-Item -Path $sourceReflector -Destination $InstallRoot -Recurse -Force
$gitDir = Join-Path $InstallRoot 'reflector/.git'
if (Test-Path $gitDir) {
    Remove-Item -Path $gitDir -Recurse -Force -ErrorAction SilentlyContinue
}

$pythonCmd = Resolve-Python
Write-Info "Python 실행 파일: $pythonCmd"
$venvPath = Join-Path $InstallRoot '.venv'
if (Test-Path $venvPath) {
    Remove-Item -Path $venvPath -Recurse -Force
}
Invoke-Python $pythonCmd "-m venv `"$venvPath`""
$pythonExe = Join-Path $venvPath 'Scripts/python.exe'
if (-not (Test-Path $pythonExe)) {
    throw "가상환경 python.exe 를 찾지 못했습니다."
}

$requirements = Join-Path $InstallRoot 'reflector/requirements.txt'
Invoke-Python $pythonExe "-m pip install --upgrade pip"
Invoke-Python $pythonExe "-m pip install -r `"$requirements`""

$runScript = Join-Path $InstallRoot 'Run-Reflector.ps1'
@"
`$env:PYTHONPATH = `"`$(Join-Path $InstallRoot 'reflector/src')`"
& `"$pythonExe`" -m agent.main --config `"`$(Join-Path $InstallRoot 'reflector/config.json')`"
"@ | Set-Content -Path $runScript -Encoding UTF8

Write-Info "REFLECTOR 설치가 완료되었습니다. Run-Reflector.ps1 스크립트를 실행하여 에이전트를 시작하세요."
