Param(
    [string]$PackageName = "MirrorStage.Ego",
    [string]$Version = "1.0.0.0",
    [string]$Publisher = "CN=DARC0625",
    [string]$PublisherDisplayName = "MIRROR STAGE",
    [string]$DisplayName = "MIRROR STAGE EGO",
    [string]$Description = "Digital twin HUD and command center",
    [string]$OutputDir = "$PSScriptRoot/output",
    [switch]$Pack
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$layoutDir = Join-Path $OutputDir 'layout'
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}
if (Test-Path $layoutDir) {
    Remove-Item -Path $layoutDir -Recurse -Force
}
New-Item -ItemType Directory -Path $layoutDir | Out-Null

Write-Host "[msix] Building bootstrapper" -ForegroundColor Cyan
$bootstrapperProject = Join-Path $repoRoot 'packaging/bootstrapper/MirrorStageBootstrapper.csproj'
$publishDir = Join-Path $layoutDir 'bootstrapper'
dotnet publish $bootstrapperProject -c Release -r win-x64 --self-contained false -o $publishDir | Out-Null
Move-Item -Path (Join-Path $publishDir 'MirrorStageBootstrapper.exe') -Destination (Join-Path $layoutDir 'MirrorStageBootstrapper.exe')
Remove-Item -Path $publishDir -Recurse -Force

Write-Host "[msix] Copying payload" -ForegroundColor Cyan
Copy-Item -Path (Join-Path $repoRoot 'packaging/install-mirror-stage-ego.ps1') -Destination $layoutDir -Force
Copy-Item -Path (Join-Path $repoRoot 'ego') -Destination (Join-Path $layoutDir 'ego') -Recurse -Force
if (Test-Path (Join-Path $repoRoot 'assets')) {
    Copy-Item -Path (Join-Path $repoRoot 'assets') -Destination (Join-Path $layoutDir 'assets') -Recurse -Force
}

$assetsDir = Join-Path $layoutDir 'Assets'
New-Item -ItemType Directory -Path $assetsDir | Out-Null
$iconSource = Join-Path $repoRoot 'ego/frontend/web/icons'
$iconMap = @{
    'Square150x150Logo.png' = 'Icon-512.png'
    'Square44x44Logo.png' = 'Icon-192.png'
    'Wide310x150Logo.png' = 'Icon-512.png'
    'Square71x71Logo.png' = 'Icon-192.png'
    'Square310x310Logo.png' = 'Icon-512.png'
    'SplashScreen.png' = 'Icon-maskable-512.png'
    'StoreLogo.png' = 'Icon-192.png'
}
foreach ($target in $iconMap.Keys) {
    $sourceFile = Join-Path $iconSource $iconMap[$target]
    if (-not (Test-Path $sourceFile)) {
        throw "Missing icon asset: $sourceFile"
    }
    Copy-Item -Path $sourceFile -Destination (Join-Path $assetsDir $target)
}

$manifestTemplate = Get-Content (Join-Path $PSScriptRoot 'templates/AppxManifest.template.xml') -Raw
$manifest = $manifestTemplate
$manifest = $manifest.Replace('__IDENTITY_NAME__', $PackageName)
$manifest = $manifest.Replace('__PUBLISHER__', $Publisher)
$manifest = $manifest.Replace('__VERSION__', $Version)
$manifest = $manifest.Replace('__DISPLAY_NAME__', $DisplayName)
$manifest = $manifest.Replace('__PUBLISHER_DISPLAY_NAME__', $PublisherDisplayName)
$manifest = $manifest.Replace('__DESCRIPTION__', $Description)
Set-Content -Path (Join-Path $layoutDir 'AppxManifest.xml') -Value $manifest -Encoding UTF8

Write-Host "[msix] Layout ready at $layoutDir" -ForegroundColor Green
if (-not $Pack) {
    Write-Host "Run 'makeappx.exe pack /d layout /p MirrorStage_Ego.msix' and sign the output to distribute via WinGet." -ForegroundColor Yellow
    return
}

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if (-not $makeAppx) {
    throw "makeappx.exe not found. Install Windows SDK or omit -Pack."
}
$sanitized = ($PackageName -replace '\\|\s', '')
$msixPath = Join-Path $OutputDir ("{0}_{1}.msix" -f $sanitized, $Version)
& $makeAppx.Source pack /d $layoutDir /p $msixPath | Out-Null
Write-Host "[msix] Created package $msixPath" -ForegroundColor Green
