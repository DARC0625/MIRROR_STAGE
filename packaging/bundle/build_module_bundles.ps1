Param(
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$bundleRoot = if ($OutputDir) { Resolve-Path $OutputDir -ErrorAction SilentlyContinue } else { $null }
if (-not $bundleRoot) {
    $bundleRoot = Join-Path $repoRoot 'packaging/bundles'
}
if (Test-Path $bundleRoot) {
    Remove-Item -Path $bundleRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $bundleRoot | Out-Null

function New-Bundle {
    param(
        [string]$Name,
        [scriptblock]$ContentBuilder
    )

    $tempDir = Join-Path $bundleRoot $Name
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    & $ContentBuilder $tempDir

    $zipPath = Join-Path $bundleRoot ("{0}.zip" -f $Name)
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $zipPath -Force
    Remove-Item -Path $tempDir -Recurse -Force
}

New-Bundle -Name 'mirror-stage-ego-bundle' -ContentBuilder {
    param($target)
    Copy-Item -Path (Join-Path $repoRoot 'packaging/install-mirror-stage-ego.ps1') -Destination $target -Force
    Copy-Item -Path (Join-Path $repoRoot 'ego') -Destination (Join-Path $target 'ego') -Recurse -Force
}

New-Bundle -Name 'mirror-stage-reflector-bundle' -ContentBuilder {
    param($target)
    Copy-Item -Path (Join-Path $repoRoot 'packaging/install-mirror-stage-reflector.ps1') -Destination $target -Force
    Copy-Item -Path (Join-Path $repoRoot 'reflector') -Destination (Join-Path $target 'reflector') -Recurse -Force
}

Write-Host "Created bundles under $bundleRoot" -ForegroundColor Green
