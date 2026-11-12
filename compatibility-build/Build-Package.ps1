param(
    [string]$SourceRoot,
    [string]$Executable,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'output')
)
$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot
if (-not $SourceRoot) {
    $siblingSource = Join-Path $packageRoot '..\source-proxy'
    $SourceRoot = if (Test-Path -LiteralPath $siblingSource) { $siblingSource } else { Join-Path $packageRoot '..' }
}
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
if (-not $Executable) { $Executable = Join-Path $SourceRoot 'target\release\cursor-byok-desktop.exe' }
$Executable = (Resolve-Path -LiteralPath $Executable).Path
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$payloadRoot = Join-Path $packageRoot 'payload'
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
$sourceZip = Join-Path $payloadRoot 'Cursor-BYOK-1.0.1-compat-source.zip'

Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $sourceZip) { Remove-Item -LiteralPath $sourceZip }
$archive = [IO.Compression.ZipFile]::Open($sourceZip, [IO.Compression.ZipArchiveMode]::Create)
try {
    if (Test-Path -LiteralPath (Join-Path $SourceRoot '.git')) {
        $sourceFiles = & git -C $SourceRoot -c core.quotepath=false ls-files
        if ($LASTEXITCODE -ne 0) { throw 'Failed to enumerate tracked source files' }
    } else {
        $sourceFiles = Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force | ForEach-Object {
            $_.FullName.Substring($SourceRoot.Length + 1).Replace('\', '/')
        } | Where-Object {
            $_ -notmatch '(^|/)(\.git|node_modules|target)(/|$)' -and
            $_ -notmatch '^compatibility-build/' -and
            $_ -notmatch '^apps/desktop/dist/' -and
            $_ -notmatch '(^|/)\.env($|\.)'
        }
    }
    foreach ($relativePath in $sourceFiles) {
        $sourcePath = Join-Path $SourceRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $sourcePath, $relativePath.Replace('\','/'), [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
    foreach ($supportFile in @('Apply-Compatibility.ps1','hooks.nsh','INSTALL-CN.md','BUILD-CN.md','Build-Package.ps1','Test-Compatibility.py','compatibility.patch')) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $packageRoot $supportFile), ('compatibility-build/' + $supportFile), [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }

$targetRoot = Join-Path $SourceRoot 'target\release'
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
$bundleExecutable = Join-Path $targetRoot 'cursor-byok-desktop.exe'
if ($Executable -ne $bundleExecutable) { Copy-Item -LiteralPath $Executable -Destination $bundleExecutable -Force }

$resources = [ordered]@{}
$resources[$sourceZip] = 'source/Cursor-BYOK-1.0.1-compat-source.zip'
$resources[(Join-Path $packageRoot 'Apply-Compatibility.ps1')] = 'compatibility/Apply-Compatibility.ps1'
$resources[(Join-Path $packageRoot 'INSTALL-CN.md')] = 'compatibility/README-CN.md'
$configuration = [ordered]@{
    bundle = [ordered]@{
        createUpdaterArtifacts = $false
        resources = $resources
        windows = @{ nsis = @{
            installerHooks = (Join-Path $packageRoot 'hooks.nsh')
            languages = @('SimpChinese','English')
            displayLanguageSelector = $true
        } }
    }
}
$configurationPath = Join-Path $packageRoot 'bundle-config.generated.json'
$configuration | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configurationPath -Encoding utf8
$env:npm_config_cache = Join-Path $packageRoot 'npm-cache'
$env:npm_config_registry = 'https://registry.npmmirror.com'
$env:TAURI_BUNDLER_CACHE_DIR = Join-Path $packageRoot 'tauri-cache'
Push-Location (Join-Path $SourceRoot 'apps\desktop')
try {
    & npm.cmd exec --yes --package=@tauri-apps/cli@2.11.4 -- tauri bundle --bundles nsis --features tauri/custom-protocol --config $configurationPath --ci --no-sign
    if ($LASTEXITCODE -ne 0) { throw "Installer packaging failed: $LASTEXITCODE" }
} finally { Pop-Location }
$installer = Get-ChildItem -LiteralPath (Join-Path $targetRoot 'bundle\nsis') -Filter '*-setup.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $installer) { throw 'NSIS installer not found' }
$outputPath = Join-Path $OutputDirectory 'Cursor.BYOK_1.0.1-compat.20261111_x64-setup.exe'
Copy-Item -LiteralPath $installer.FullName -Destination $outputPath -Force
$manifest = [ordered]@{
    installer = (Split-Path $outputPath -Leaf)
    installerSHA256 = (Get-FileHash -LiteralPath $outputPath).Hash
    executableSHA256 = (Get-FileHash -LiteralPath $bundleExecutable).Hash
    sourceSHA256 = (Get-FileHash -LiteralPath $sourceZip).Hash
    upstreamCommit = '2068ab20513288e6a0289d33febe872a30608610'
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256.json') -Encoding utf8
Write-Output "Installer: $outputPath"
