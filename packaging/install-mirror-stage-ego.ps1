Param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\MIRROR_STAGE",
    [string]$RepoUrl = "https://github.com/DARC0625/MIRROR_STAGE.git",
    [string]$Branch = "main",
    [switch]$ForceRepoSync,
    [string]$ProgressLogPath
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
$script:ProgressLogPath = $null
$script:ProgressStep = 0
$script:ProgressTotal = 8

if ($ProgressLogPath) {
    try {
        New-Item -ItemType File -Path $ProgressLogPath -Force | Out-Null
        Clear-Content -Path $ProgressLogPath -ErrorAction SilentlyContinue
        $script:ProgressLogPath = $ProgressLogPath
    } catch {
        $script:ProgressLogPath = $null
    }
}

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

function Write-ProgressRecord {
    param(
        [string]$Kind,
        [string]$Payload
    )

    if ($script:ProgressLogPath) {
        Add-Content -Path $script:ProgressLogPath -Value ("@@{0}|{1}" -f $Kind, $Payload)
    }
}

function Write-Log {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [switch]$SkipBroadcast
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $line
    try { Write-Host $Message -ForegroundColor $Color } catch { Write-Host $Message }
    if (-not $SkipBroadcast) {
        Write-ProgressRecord -Kind 'LOG' -Payload $Message
    }
}

function Start-Step {
    param(
        [string]$Message
    )

    $script:ProgressStep += 1
    $formatted = "[Step {0}/{1}] {2}" -f $script:ProgressStep, $script:ProgressTotal, $Message
    Write-Log $formatted ([ConsoleColor]::DarkGray)
    Write-ProgressRecord -Kind 'PROGRESS' -Payload ("{0}|{1}|{2}" -f $script:ProgressStep, $script:ProgressTotal, $Message)
    Publish-Status $Message
}

function Publish-Status {
    param(
        [string]$Message
    )

    Write-ProgressRecord -Kind 'STATUS' -Payload $Message
}

function Download-File {
    param(
        [string]$Uri,
        [string]$Destination,
        [string]$Description
    )

    Write-Log "[Installer] Downloading $Description from $Uri" ([ConsoleColor]::DarkGray)
    Publish-Status ("Downloading {0}..." -f $Description)
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue | Out-Null
    $handler = $null
    $client = $null
    $response = $null
    $stream = $null
    $fileStream = $null
    try {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromMinutes(60)
        $response = $client.GetAsync($Uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode()
        $totalBytes = $response.Content.Headers.ContentLength
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $fileStream = [System.IO.FileStream]::new($Destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

        $buffer = New-Object byte[] 1048576
        $readBytes = 0L
        $lastPercent = -1
        $lastLoggedPercent = -10
        $lastLoggedMegabytes = -1
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $bytesRead)
            $readBytes += $bytesRead
            if ($totalBytes -and $totalBytes -gt 0) {
                $percent = [int](($readBytes * 100) / $totalBytes)
                if ($percent -ne $lastPercent) {
                    $status = "{0}% ({1:n1} MB / {2:n1} MB)" -f $percent, ($readBytes / 1MB), ($totalBytes / 1MB)
                    Publish-Status ("Downloading {0}: {1}" -f $Description, $status)
                    if (($percent -ge $lastLoggedPercent + 10) -or ($percent -eq 100)) {
                        Write-Log "[Installer] $Description download progress: $status" ([ConsoleColor]::DarkGray)
                        $lastLoggedPercent = $percent
                    }
                    $lastPercent = $percent
                }
            } else {
                $currentMb = [int]($readBytes / 1MB)
                if (($currentMb -ne $lastLoggedMegabytes) -and ($currentMb % 50 -eq 0)) {
                    $status = "{0:n0} MB downloaded" -f $currentMb
                    Publish-Status ("Downloading {0}: {1}" -f $Description, $status)
                    Write-Log "[Installer] $Description download progress: $status" ([ConsoleColor]::DarkGray)
                    $lastLoggedMegabytes = $currentMb
                }
            }
        }
        $stopwatch.Stop()
    } catch {
        throw "Failed to download $Description from $Uri. $_"
    } finally {
        if ($fileStream) { $fileStream.Flush(); $fileStream.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        if ($client) { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    }
    Publish-Status ("Completed download: {0}" -f $Description)
    Write-Log "[Installer] Finished downloading $Description" ([ConsoleColor]::Green)
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
    Write-Log "[Installer] Extracting Flutter archive (this can take a few minutes)" ([ConsoleColor]::DarkGray)
    Publish-Status "Extracting Flutter archive..."
    $extractStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $extracted = $false
    try {
        Expand-Archive -Path $archivePath -DestinationPath $ToolsDir -Force
        $extracted = $true
    } catch {
        Write-Log "[Installer] Expand-Archive failed: $_. Trying tar.exe fallback." ([ConsoleColor]::Yellow)
        $tar = Get-Command tar -ErrorAction SilentlyContinue
        if ($tar) {
            & $tar.Source -xf $archivePath -C $ToolsDir >> $logFile 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe failed to extract Flutter archive (ExitCode: $LASTEXITCODE)"
            }
            $extracted = $true
        } else {
            throw
        }
    }
    $extractStopwatch.Stop()
    Remove-Item -Path $archivePath -Force
    if (-not (Test-Path $flutterExe)) {
        throw "Flutter extraction failed. Did not find $flutterExe."
    }
    Set-Content -Path $versionMarker -Value $release.Version
    if ($extracted) {
        Write-Log "[Installer] Flutter archive extracted in $([Math]::Round($extractStopwatch.Elapsed.TotalMinutes, 2)) minutes." ([ConsoleColor]::DarkGray)
    }
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
    Publish-Status "Starting installation..."

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

    Start-Step "Preparing Node.js runtime"
    $node = Ensure-NodeRuntime -ToolsDir $toolsDir

    Start-Step "Preparing Flutter SDK"
    $flutter = Ensure-FlutterSdk -ToolsDir $toolsDir

    # Update runtime PATH for child processes within this installer
    $nodeBin = Split-Path -Parent $node.Node
    $flutterBin = Split-Path -Parent $flutter.Flutter
    $env:Path = "$nodeBin;$flutterBin;$env:Path"

    Start-Step "Installing backend dependencies (npm ci)"
    Invoke-LoggedProcess -FilePath $node.Npm -Arguments "ci" -WorkingDirectory $backendDir -Description "npm ci (backend)"

    Start-Step "Building backend application (npm run build)"
    Invoke-LoggedProcess -FilePath $node.Npm -Arguments "run build" -WorkingDirectory $backendDir -Description "npm run build (backend)"

    Start-Step "Configuring Flutter for web builds"
    Invoke-LoggedProcess -FilePath $flutter.Flutter -Arguments "config --enable-web" -WorkingDirectory $frontendDir -Description "flutter config --enable-web"

    Start-Step "Resolving Flutter packages"
    Invoke-LoggedProcess -FilePath $flutter.Flutter -Arguments "pub get" -WorkingDirectory $frontendDir -Description "flutter pub get"

    Start-Step "Building Flutter web bundle"
    Invoke-LoggedProcess -FilePath $flutter.Flutter -Arguments "build web --release --dart-define=MIRROR_STAGE_WS_URL=http://localhost:3000/digital-twin" -WorkingDirectory $frontendDir -Description "flutter build web --release"

    Start-Step "Validating toolchain versions"
    Write-Log "[Installer] Node version" ([ConsoleColor]::DarkGray)
    & $node.Node --version >> $logFile 2>&1
    Write-Log "[Installer] Flutter version" ([ConsoleColor]::DarkGray)
    & $flutter.Flutter --version >> $logFile 2>&1

    Write-Log "[Installer] MIRROR STAGE EGO installation completed successfully." ([ConsoleColor]::Green)
    Publish-Status "Installation completed successfully."
} catch {
    Write-Log "[Installer] Error: $_" ([ConsoleColor]::Red)
    Write-Log "See $logFile for details." ([ConsoleColor]::Red)
    Publish-Status "Installation failed. See log for details."
    throw
}
