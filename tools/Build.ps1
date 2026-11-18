param(
    [string]$ViewpointJar = 'D:\SteamLibrary\steamapps\workshop\content\108600\3809306528\mods\Viewpoint\42\media\java\client\Viewpoint.jar',
    [string]$JdkDir
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $JdkDir) {
    $jdkFolder = Join-Path $env:USERPROFILE 'Documents\ChatGPT\PZ - Performance\build\jdk25'
    if (Test-Path -LiteralPath $jdkFolder) {
        $JdkDir = (Get-ChildItem -LiteralPath $jdkFolder -Directory | Select-Object -First 1).FullName
    } else {
        $JdkDir = $env:JAVA_HOME
    }
}
if (-not $JdkDir -or -not (Test-Path -LiteralPath (Join-Path $JdkDir 'bin\javac.exe'))) {
    throw 'Pass -JdkDir with a JDK 25 installation.'
}
$buildFolder = Join-Path $projectRoot ('build\' + [Guid]::NewGuid().ToString('N'))
$classFolder = Join-Path $buildFolder 'classes'
$apiJar = Join-Path $buildFolder 'viewpoint-api.jar'
$sourceMod = Join-Path $projectRoot 'content\mods\ViewpointBathShowerEffects'
$addonFolder = Join-Path $sourceMod '42\media\viewpoint\addons\maeiro.bath-shower-effects'
New-Item -ItemType Directory -Path $classFolder -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceArchive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ViewpointJar).Path)
$apiArchive = [System.IO.Compression.ZipFile]::Open($apiJar, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($entry in $sourceArchive.Entries) {
        if (-not $entry.FullName.StartsWith('viewpoint/api/') -or -not $entry.FullName.EndsWith('.class')) { continue }
        $copy = $apiArchive.CreateEntry($entry.FullName)
        $inputStream = $entry.Open()
        $outputStream = $copy.Open()
        try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
    }
    foreach ($base in @('default', 'somber')) {
        $baseEntry = $sourceArchive.GetEntry("viewpoint/shaderpacks/$base/pack.properties")
        if (-not $baseEntry) { throw "Viewpoint does not contain the $base shaderpack." }
        $packId = "maeiro.bath-shower-$base"
        $packFolder = Join-Path $sourceMod "42\media\viewpoint\shaderpacks\$packId"
        New-Item -ItemType Directory -Path (Join-Path $packFolder 'shaders') -Force | Out-Null
        $displayBase = if ($base -eq 'default') { 'Default' } else { 'Somber' }
        $packProperties = @"
format=1
id=$packId
name=$displayBase + Bath & Shower Effects
version=0.2.1
author=Maeiro
description=$displayBase with depth-tested TABAS water and steam. Enable the Bath & Shower Effects addon as well.
game.min=42.22
viewpoint.min=0.1.7
base=$base
passes=bathShower
pass.bathShower.stage=final
pass.bathShower.fragment=bath_shower.frag
pass.bathShower.inputs=color depth
options=bathWater bathSteam bathWaterStrength bathSteamStrength bathQuality bathHeight bathTubHeight bathTubDepth
option.bathWater.label=Shower and bathtub water
option.bathWater.default=true
option.bathSteam.label=Shower and bathtub steam
option.bathSteam.default=true
option.bathWaterStrength.label=Water visibility
option.bathWaterStrength.range=0 2 0.1
option.bathWaterStrength.default=1
option.bathSteamStrength.label=Steam density
option.bathSteamStrength.range=0 2 0.1
option.bathSteamStrength.default=1
option.bathQuality.label=Bath effects quality
option.bathQuality.values=low medium high
option.bathQuality.value.low=Low
option.bathQuality.value.medium=Medium
option.bathQuality.value.high=High
option.bathQuality.default=medium
option.bathHeight.label=Shower head height (squares)
option.bathHeight.range=1.5 2.3 0.05
option.bathHeight.default=1.9
option.bathTubHeight.label=Full bathtub water height (squares)
option.bathTubHeight.range=0.35 0.85 0.01
option.bathTubHeight.default=0.52
option.bathTubDepth.label=Bathtub water depth (squares)
option.bathTubDepth.range=0.10 0.34 0.01
option.bathTubDepth.default=0.34
"@
        [System.IO.File]::WriteAllText((Join-Path $packFolder 'pack.properties'), $packProperties + "`n")
        Copy-Item -LiteralPath (Join-Path $projectRoot 'src\shaders\bath_shower.frag') -Destination (Join-Path $packFolder 'shaders\bath_shower.frag') -Force
    }
} finally {
    $apiArchive.Dispose()
    $sourceArchive.Dispose()
}
$sources = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src\main\java') -Filter *.java -Recurse -File)
& (Join-Path $JdkDir 'bin\javac.exe') --release 17 -encoding UTF-8 -g:none -classpath $apiJar -d $classFolder @($sources.FullName)
if ($LASTEXITCODE -ne 0) { throw 'Addon compilation failed.' }
$outputJar = Join-Path $addonFolder 'bath-shower-effects.jar'
& (Join-Path $JdkDir 'bin\jar.exe') --create --file $outputJar --date=2026-01-01T00:00:00Z -C $classFolder .
if ($LASTEXITCODE -ne 0) { throw 'Addon packaging failed.' }
$entries = & (Join-Path $JdkDir 'bin\jar.exe') tf $outputJar
if ($entries | Where-Object { $_ -like 'viewpoint/api/*' }) { throw 'Addon bundles the Viewpoint API.' }
$packageFolder = Join-Path $projectRoot 'dist\ViewpointBathShowerEffects'
$packageMod = Join-Path $packageFolder 'Contents\mods\ViewpointBathShowerEffects'
New-Item -ItemType Directory -Path $packageMod -Force | Out-Null
Copy-Item -Path (Join-Path $sourceMod '*') -Destination $packageMod -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $packageFolder 'README.md') -Force
Compress-Archive -Path $packageFolder -DestinationPath (Join-Path $projectRoot 'dist\ViewpointBathShowerEffects.zip') -Force
Write-Output "Built Java 17 addon and Default/Somber variants: $packageMod"
Write-Output "Validation API/classes: $buildFolder"
