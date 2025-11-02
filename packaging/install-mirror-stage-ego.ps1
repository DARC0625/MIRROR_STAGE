Param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\MIRROR_STAGE",
    [string]$RepoUrl = "https://github.com/DARC0625/MIRROR_STAGE.git",
    [string]$Branch = "main"
)

function Ensure-Directory($Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

Ensure-Directory -Path $InstallRoot
$logDir = Join-Path $InstallRoot "logs"
Ensure-Directory -Path $logDir
$logFile = Join-Path $logDir ("install-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".log")

function Write-Log {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $line
    try { Write-Host $Message -ForegroundColor $Color } catch { Write-Host $Message }
}

function Invoke-WingetInstall {
    param(
        [string]$Id,
        [string]$Description
    )
    Write-Log "[Installer] winget install: $Description ($Id)" ([ConsoleColor]::DarkGray)
    $args = "install --silent --accept-source-agreements --accept-package-agreements --id `"$Id`" -e --source winget"
    $process = Start-Process winget -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        $listArgs = "list --id `"$Id`" -e"
        $listOutput = & winget $listArgs
        if ($LASTEXITCODE -eq 0 -and ($listOutput -match $Id)) {
            Write-Log "[Installer] $Description already installed (winget exit code $($process.ExitCode))." ([ConsoleColor]::Yellow)
        } else {
            throw "winget install failed: $Description (ExitCode: $($process.ExitCode))"
        }
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
            Write-Log "[Installer] Found $FriendlyName at $($command.Path)" ([ConsoleColor]::DarkGray)
            return $command.Path
        }
    }
    foreach ($candidate in $CandidatePaths) {
        if (Test-Path $candidate) {
            Write-Log "[Installer] Using candidate path for $FriendlyName: $candidate" ([ConsoleColor]::DarkGray)
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
    Write-Log "[Installer] Running: $Description" ([ConsoleColor]::DarkGray)
    Push-Location $WorkingDirectory
    & $env:ComSpec /c "$Command" >> $logFile 2>&1
    $exitCode = $LASTEXITCODE
    Pop-Location
    if ($exitCode -ne 0) {
        throw "$Description failed (ExitCode: $exitCode)"
    }
}

try {
    Write-Log "[Installer] Starting MIRROR STAGE EGO installation"

    Invoke-WingetInstall -Id "OpenJS.NodeJS.LTS" -Description "Node.js LTS"
    Invoke-WingetInstall -Id "Git.Git" -Description "Git"
    Invoke-WingetInstall -Id "Google.Flutter" -Description "Flutter SDK"

    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine')
    $flutterPaths = @(
        "C:\Program Files\Google\Flutter\bin",
        "C:\Program Files (x86)\Google\Flutter\bin",
        "$env:LOCALAPPDATA\Programs\Flutter\bin",
        "$env:LOCALAPPDATA\Programs\Flutter\flutter\bin"
    )
    foreach ($flutterPath in $flutterPaths) {
        if (Test-Path $flutterPath) {
            Write-Log "[Installer] Registering Flutter path: $flutterPath" ([ConsoleColor]::DarkGray)
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

    $nodeExe = Resolve-Executable -CommandNames @("node.exe","node") -CandidatePaths @(
        "C:\Program Files\nodejs\node.exe",
        "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
    ) -FriendlyName "Node.js"
    if (-not $nodeExe) { throw "Unable to locate Node.js executable." }

    $flutterExe = Resolve-Executable -CommandNames @("flutter.bat","flutter") -CandidatePaths $flutterPaths -FriendlyName "Flutter"
    if (-not $flutterExe) { throw "Unable to locate Flutter executable." }

    Write-Log "[Installer] Preparing install root: $InstallRoot"
    Set-Location $InstallRoot

    if (-not (Test-Path "$InstallRoot\MIRROR_STAGE")) {
        Write-Log "[Installer] Cloning repository: $RepoUrl ($Branch)" ([ConsoleColor]::DarkGray)
        git clone --branch $Branch $RepoUrl MIRROR_STAGE >> $logFile 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Git clone failed" }
    } else {
        Write-Log "[Installer] Updating existing installation" ([ConsoleColor]::DarkGray)
        Push-Location "$InstallRoot\MIRROR_STAGE"
        git fetch --all >> $logFile 2>&1
        git reset --hard origin/$Branch >> $logFile 2>&1
        Pop-Location
    }

    $backendDir = "$InstallRoot\MIRROR_STAGE\ego\backend"
    $frontendDir = "$InstallRoot\MIRROR_STAGE\ego\frontend"

    Invoke-LoggedCommand -Command "npm install" -WorkingDirectory $backendDir -Description "npm install"
    Invoke-LoggedCommand -Command "flutter pub get" -WorkingDirectory $frontendDir -Description "flutter pub get"

    Write-Log "[Installer] node --version" ([ConsoleColor]::DarkGray)
    & $nodeExe --version >> $logFile 2>&1
    Write-Log "[Installer] flutter --version" ([ConsoleColor]::DarkGray)
    & $flutterExe --version >> $logFile 2>&1

    Write-Log "[Installer] MIRROR STAGE EGO installation completed successfully." ([ConsoleColor]::Green)
} catch {
    Write-Log "[Installer] Error: $_" ([ConsoleColor]::Red)
    Write-Log "See $logFile for details." ([ConsoleColor]::Red)
    throw
}
