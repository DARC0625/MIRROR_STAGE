Param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\MIRROR_STAGE",
    [string]$RepoUrl = "https://github.com/DARC0625/MIRROR_STAGE.git",
    [string]$Branch = "main"
)

Write-Host "[Installer] Installing prerequisites via winget..."
$wingetArgs = "install", "--silent", "--accept-source-agreements", "--accept-package-agreements"

Start-Process winget -ArgumentList ($wingetArgs + @("--id", "OpenJS.NodeJS.LTS", "-e", "--source", "winget")) -Wait -NoNewWindow
Start-Process winget -ArgumentList ($wingetArgs + @("--id", "Git.Git", "-e", "--source", "winget")) -Wait -NoNewWindow
Start-Process winget -ArgumentList ($wingetArgs + @("--id", "Google.Flutter", "-e", "--source", "winget")) -Wait -NoNewWindow

$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')

Write-Host "[Installer] Configuring PATH entries..."
$flutterDefaultPaths = @(
    "C:\Program Files\Google\Flutter\bin",
    "C:\Program Files (x86)\Google\Flutter\bin",
    "$env:LOCALAPPDATA\Programs\Flutter\bin"
)
foreach ($flutterPath in $flutterDefaultPaths) {
    if (Test-Path $flutterPath) {
        if (-not $env:Path.Split(';') -contains $flutterPath) {
            $env:Path = "$env:Path;$flutterPath"
        }
        $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
        if ($machinePath -notmatch [Regex]::Escape($flutterPath)) {
            [Environment]::SetEnvironmentVariable('Path',"$machinePath;$flutterPath",[EnvironmentVariableTarget]::Machine)
        }
        Write-Host " - Flutter path registered: $flutterPath"
        break
    }
}

Write-Host "[Installer] Preparing target directory $InstallRoot"
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
Set-Location $InstallRoot

if (-not (Test-Path "$InstallRoot\\MIRROR_STAGE")) {
    Write-Host "[Installer] Cloning repository $RepoUrl ($Branch)..."
    git clone --branch $Branch $RepoUrl MIRROR_STAGE
} else {
    Write-Host "[Installer] Existing MIRROR_STAGE directory detected, pulling latest..."
    Set-Location "$InstallRoot\\MIRROR_STAGE"
    git fetch --all
    git reset --hard origin/$Branch
    Set-Location $InstallRoot
}

Write-Host "[Installer] Installing backend dependencies..."
Set-Location "$InstallRoot\\MIRROR_STAGE\\ego\\backend"
npm install

Write-Host "[Installer] Fetching frontend packages..."
Set-Location "$InstallRoot\\MIRROR_STAGE\\ego\\frontend"
flutter pub get

Write-Host "[Installer] MIRROR STAGE EGO setup complete."
Write-Host "Backend: cd $InstallRoot\\MIRROR_STAGE\\ego\\backend && npm run start:dev"
Write-Host "Frontend: cd $InstallRoot\\MIRROR_STAGE\\ego\\frontend && flutter run -d edge --web-hostname=0.0.0.0 --web-port=8080 --dart-define=MIRROR_STAGE_WS_URL=http://10.0.0.100:3000/digital-twin"
