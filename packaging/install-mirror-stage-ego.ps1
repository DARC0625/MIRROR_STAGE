Param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\MIRROR_STAGE",
    [string]$RepoUrl = "https://github.com/DARC0625/MIRROR_STAGE.git",
    [string]$Branch = "main"
)

function New-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

New-Directory -Path $InstallRoot
$logDir = Join-Path $InstallRoot "logs"
New-Directory -Path $logDir
$logFile = Join-Path $logDir ("install-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".log")

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

function Invoke-WingetInstall {
    param(
        [string]$Id,
        [string]$Description
    )
    Write-Log "[Installer] winget 설치: $Description ($Id)" ([ConsoleColor]::DarkGray)
    $args = "install --silent --accept-source-agreements --accept-package-agreements --id `"$Id`" -e --source winget"
    $process = Start-Process winget -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        throw "winget 설치 실패: $Description (ExitCode: $($process.ExitCode))"
    }
}

function Resolve-Executable {
    param(
        [string[]]$CommandNames,
        [string[]]$CandidatePaths,
        [string]$FriendlyName
    )

    foreach ($name in $CommandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            Write-Log "[Installer] $FriendlyName 위치: $($command.Path)" ([ConsoleColor]::DarkGray)
            return $command.Path
        }
    }

    foreach ($candidate in $CandidatePaths) {
        if (Test-Path $candidate) {
            Write-Log "[Installer] $FriendlyName 후보 사용: $candidate" ([ConsoleColor]::DarkGray)
            return $candidate
        }
    }
    return $null
}

function Invoke-LoggedCommand {
    param(
        [string]$Command,
        [string]$WorkingDirectory,
        [string]$Description
    )

    Write-Log "[Installer] 실행: $Description" ([ConsoleColor]::DarkGray)
    Push-Location $WorkingDirectory
    & $env:ComSpec /c "$Command" >> $logFile 2>&1
    $exitCode = $LASTEXITCODE
    Pop-Location
    if ($exitCode -ne 0) {
        throw "$Description 실행 실패 (ExitCode: $exitCode)"
    }
}

try {
    Write-Log "[Installer] MIRROR STAGE EGO 설치 시작"

    Invoke-WingetInstall -Id "OpenJS.NodeJS.LTS" -Description "Node.js LTS"
    Invoke-WingetInstall -Id "Git.Git" -Description "Git"
    Invoke-WingetInstall -Id "Google.Flutter" -Description "Flutter SDK"

    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine')
    $flutterDefaultPaths = @(
        "C:\Program Files\Google\Flutter\bin",
        "C:\Program Files (x86)\Google\Flutter\bin",
        "$env:LOCALAPPDATA\Programs\Flutter\bin",
        "$env:LOCALAPPDATA\Programs\Flutter\flutter\bin"
    )
    foreach ($flutterPath in $flutterDefaultPaths) {
        if (Test-Path $flutterPath) {
            Write-Log "[Installer] Flutter PATH 등록: $flutterPath" ([ConsoleColor]::DarkGray)
            if (-not ($env:Path.Split(';') -contains $flutterPath)) {
                $env:Path = "$env:Path;$flutterPath"
            }
            $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
            if ($machinePath -notmatch [Regex]::Escape($flutterPath)) {
                [Environment]::SetEnvironmentVariable('Path',"$machinePath;$flutterPath",[EnvironmentVariableTarget]::Machine)
            }
            break
        }
    }

    $nodePath = Resolve-Executable -CommandNames @("node.exe","node") -CandidatePaths @(
        "C:\Program Files\nodejs\node.exe",
        "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
    ) -FriendlyName "Node.js"
    if (-not $nodePath) {
        throw "Node.js 실행 파일을 찾을 수 없습니다."
    }

    $flutterExe = Resolve-Executable -CommandNames @("flutter.bat","flutter") -CandidatePaths $flutterDefaultPaths -FriendlyName "Flutter"
    if (-not $flutterExe) {
        throw "Flutter 실행 파일을 찾을 수 없습니다."
    }

    Write-Log "[Installer] 준비 중: $InstallRoot"
    Set-Location $InstallRoot

    if (-not (Test-Path "$InstallRoot\MIRROR_STAGE")) {
        Write-Log "[Installer] 저장소 클론: $RepoUrl ($Branch)" ([ConsoleColor]::DarkGray)
        git clone --branch $Branch $RepoUrl MIRROR_STAGE >> $logFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone 실패"
        }
    } else {
        Write-Log "[Installer] 기존 설치 갱신" ([ConsoleColor]::DarkGray)
        Push-Location "$InstallRoot\MIRROR_STAGE"
        git fetch --all >> $logFile 2>&1
        git reset --hard origin/$Branch >> $logFile 2>&1
        Pop-Location
    }

    $backendDir = "$InstallRoot\MIRROR_STAGE\ego\backend"
    $frontendDir = "$InstallRoot\MIRROR_STAGE\ego\frontend"

    Invoke-LoggedCommand -Command "npm install" -WorkingDirectory $backendDir -Description "npm install"
    Invoke-LoggedCommand -Command "flutter pub get" -WorkingDirectory $frontendDir -Description "flutter pub get"

    Write-Log "[Installer] node --version 확인" ([ConsoleColor]::DarkGray)
    & $nodePath --version >> $logFile 2>&1
    Write-Log "[Installer] flutter --version 확인" ([ConsoleColor]::DarkGray)
    & $flutterExe --version >> $logFile 2>&1

    Write-Log "[Installer] MIRROR STAGE EGO 설치가 완료되었습니다." ([ConsoleColor]::Green)
} catch {
    Write-Log "[Installer] 오류: $_" ([ConsoleColor]::Red)
    Write-Log "자세한 내용은 $logFile 을 확인하세요." ([ConsoleColor]::Red)
    throw
}
