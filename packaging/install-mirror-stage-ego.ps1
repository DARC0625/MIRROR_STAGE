Param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\MIRROR_STAGE",
    [string]$RepoUrl = "https://github.com/DARC0625/MIRROR_STAGE.git",
    [string]$Branch = "main",
    [switch]$ForceRepoSync
)

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

Ensure-Directory -Path $InstallRoot
$logDir = Join-Path $InstallRoot "logs"
Ensure-Directory -Path $logDir
$logFile = Join-Path $logDir ("install-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".log")

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {
    # Older .NET Framework builds may not expose TLS 1.3
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Log "[Installer] Warning: Failed to enforce TLS 1.2+. Downloads may fail on legacy systems." ([ConsoleColor]::Yellow)
    }
}

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

function Download-File {
    param(
        [string]$Uri,
        [string]$Destination,
        [string]$Description
    )

    Write-Log "[Installer] Downloading $Description from $Uri" ([ConsoleColor]::DarkGray)
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
    } catch {
        throw "Failed to download $Description from $Uri. $_"
    }
}

function Ensure-NodeRuntime {
    param(
        [string]$ToolsDir
    )

    Write-Log "[Installer] Ensuring Node.js runtime under $ToolsDir" ([ConsoleColor]::DarkGray)
    $nodeVersion = "20.17.0"
    $nodeArchiveName = "node-v$nodeVersion-win-x64.zip"
    $nodeDownloadUrl = "https://nodejs.org/dist/v$nodeVersion/$nodeArchiveName"
    $nodeDir = Join-Path $ToolsDir "node"
    $nodeExe = Join-Path $nodeDir "node.exe"
    $npmCmd = Join-Path $nodeDir "npm.cmd"

    $hasNode = Test-Path $nodeExe
    $hasNpm = Test-Path $npmCmd
    if ($hasNode -and $hasNpm) {
        Write-Log "[Installer] Bundled Node.js already present at $nodeExe" ([ConsoleColor]::DarkGray)
        return @{ Node = $nodeExe; Npm = $npmCmd }
    }

    Ensure-Directory -Path $ToolsDir
    $tempArchive = Join-Path $env:TEMP $nodeArchiveName
    Download-File -Uri $nodeDownloadUrl -Destination $tempArchive -Description "Node.js $nodeVersion"

    if (Test-Path $nodeDir) {
        Remove-Item -Path $nodeDir -Recurse -Force
    }
    Expand-Archive -Path $tempArchive -DestinationPath $ToolsDir -Force
    $extractedDir = Join-Path $ToolsDir ("node-v{0}-win-x64" -f $nodeVersion)
    if (-not (Test-Path $extractedDir)) {
        throw "Node.js archive extraction failed. Expected $extractedDir."
    }
    Rename-Item -Path $extractedDir -NewName "node"
    Remove-Item -Path $tempArchive -Force

    Write-Log "[Installer] Node.js $nodeVersion installed to $nodeDir" ([ConsoleColor]::Green)
    return @{ Node = $nodeExe; Npm = $npmCmd }
}

function Get-LatestFlutterRelease {
    $manifestUrl = "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
    Write-Log "[Installer] Fetching Flutter release manifest" ([ConsoleColor]::DarkGray)
    $manifest = Invoke-RestMethod -Uri $manifestUrl -ErrorAction Stop
    $stableHash = $manifest.current_release.stable
    $release = $manifest.releases | Where-Object { $_.hash -eq $stableHash -and $_.dart_sdk_arch -eq "x64" } | Select-Object -First 1
    if (-not $release) {
        throw "Unable to determine latest stable Flutter release."
    }
    $archiveUrl = "https://storage.googleapis.com/flutter_infra_release/releases/$($release.archive)"
    return @{
        Version = $release.version
        ArchiveUrl = $archiveUrl
        ArchiveName = Split-Path -Leaf $release.archive
    }
}

function Ensure-FlutterSdk {
    param(
        [string]$ToolsDir
    )

    Write-Log "[Installer] Ensuring Flutter SDK under $ToolsDir" ([ConsoleColor]::DarkGray)
    $flutterDir = Join-Path $ToolsDir "flutter"
    $flutterExe = Join-Path $flutterDir "bin\flutter.bat"
    $versionMarker = Join-Path $flutterDir "MIRROR_STAGE_VERSION.txt"

    $release = Get-LatestFlutterRelease

    $flutterExists = Test-Path $flutterExe
    $versionFileExists = Test-Path $versionMarker
    if ($flutterExists -and $versionFileExists) {
        $currentVersion = Get-Content $versionMarker -ErrorAction SilentlyContinue
        if ($currentVersion -eq $release.Version) {
            Write-Log "[Installer] Flutter $currentVersion already provisioned." ([ConsoleColor]::DarkGray)
            return @{ Flutter = $flutterExe; Version = $currentVersion }
        }
        Write-Log "[Installer] Flutter version mismatch ($currentVersion -> $($release.Version)). Refreshing SDK." ([ConsoleColor]::Yellow)
    }

    Ensure-Directory -Path $ToolsDir
    $archivePath = Join-Path $env:TEMP $release.ArchiveName
    Download-File -Uri $release.ArchiveUrl -Destination $archivePath -Description ("Flutter " + $release.Version)

    if (Test-Path $flutterDir) {
        Remove-Item -Path $flutterDir -Recurse -Force
    }
    Expand-Archive -Path $archivePath -DestinationPath $ToolsDir -Force
    Remove-Item -Path $archivePath -Force
    if (-not (Test-Path $flutterExe)) {
        throw "Flutter extraction failed. Did not find $flutterExe."
    }
    Set-Content -Path $versionMarker -Value $release.Version
    Write-Log "[Installer] Flutter $($release.Version) installed to $flutterDir" ([ConsoleColor]::Green)
    return @{ Flutter = $flutterExe; Version = $release.Version }
}

function Invoke-LoggedProcess {
    param(
        [string]$FilePath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$Description
    )

    Write-Log "[Installer] $Description" ([ConsoleColor]::DarkGray)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($stdout) { Add-Content -Path $logFile -Value $stdout }
    if ($stderr) { Add-Content -Path $logFile -Value $stderr }
    if ($process.ExitCode -ne 0) {
        throw "$Description failed (ExitCode: $($process.ExitCode))"
    }
}

try {
    Write-Log "[Installer] Starting MIRROR STAGE EGO installation"

    $egoRoot = if (Test-Path (Join-Path $InstallRoot "ego")) {
        Join-Path $InstallRoot "ego"
    } elseif (Test-Path (Join-Path $InstallRoot "MIRROR_STAGE\ego")) {
        Join-Path $InstallRoot "MIRROR_STAGE\ego"
    } else {
        Join-Path $InstallRoot "ego"
    }
    Ensure-Directory -Path $egoRoot

    $backendDir = Join-Path $egoRoot "backend"
    $frontendDir = Join-Path $egoRoot "frontend"
    $toolsDir = Join-Path $InstallRoot "tools"

    if ($ForceRepoSync) {
        Write-Log "[Installer] Force syncing repository from $RepoUrl ($Branch)" ([ConsoleColor]::Yellow)
        $gitExe = Get-Command git -ErrorAction SilentlyContinue
        if (-not $gitExe) {
            throw "Git executable not found. Install Git (winget install Git.Git) or rerun the installer without -ForceRepoSync."
        }
        if (Test-Path $egoRoot) {
            Remove-Item -Path $egoRoot -Recurse -Force
        }
        & $gitExe.Source clone --branch $Branch $RepoUrl $egoRoot >> $logFile 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Git clone failed" }
    }

    if (-not (Test-Path $backendDir) -or -not (Test-Path (Join-Path $backendDir "package.json"))) {
        throw "Backend directory is missing from the installer payload. Re-run setup or download the latest installer."
    }
    if (-not (Test-Path $frontendDir) -or -not (Test-Path (Join-Path $frontendDir "pubspec.yaml"))) {
        throw "Frontend directory is missing from the installer payload. Re-run setup or download the latest installer."
    }

    $node = Ensure-NodeRuntime -ToolsDir $toolsDir
    $flutter = Ensure-FlutterSdk -ToolsDir $toolsDir

    # Update runtime PATH for child processes within this installer
    $nodeBin = Split-Path -Parent $node.Node
    $flutterBin = Split-Path -Parent $flutter.Flutter
    $env:Path = "$nodeBin;$flutterBin;$env:Path"

    Invoke-LoggedProcess -FilePath $node.Npm -Arguments "ci" -WorkingDirectory $backendDir -Description "npm ci (backend)"
    Invoke-LoggedProcess -FilePath $node.Npm -Arguments "run build" -WorkingDirectory $backendDir -Description "npm run build (backend)"

    Invoke-LoggedProcess -FilePath $flutter.Flutter -Arguments "config --enable-web --no-version-check" -WorkingDirectory $frontendDir -Description "flutter config --enable-web"
    Invoke-LoggedProcess -FilePath $flutter.Flutter -Arguments "pub get --no-version-check" -WorkingDirectory $frontendDir -Description "flutter pub get"
    Invoke-LoggedProcess -FilePath $flutter.Flutter -Arguments "build web --release --no-version-check --dart-define=MIRROR_STAGE_WS_URL=http://localhost:3000/digital-twin" -WorkingDirectory $frontendDir -Description "flutter build web --release"

    Write-Log "[Installer] Node version" ([ConsoleColor]::DarkGray)
    & $node.Node --version >> $logFile 2>&1
    Write-Log "[Installer] Flutter version" ([ConsoleColor]::DarkGray)
    & $flutter.Flutter --version >> $logFile 2>&1

    Write-Log "[Installer] MIRROR STAGE EGO installation completed successfully." ([ConsoleColor]::Green)
} catch {
    Write-Log "[Installer] Error: $_" ([ConsoleColor]::Red)
    Write-Log "See $logFile for details." ([ConsoleColor]::Red)
    throw
}
