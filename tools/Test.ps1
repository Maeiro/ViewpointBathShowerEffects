param(
    [string]$ViewpointJar = 'D:\SteamLibrary\steamapps\workshop\content\108600\3809306528\mods\Viewpoint\42\media\java\client\Viewpoint.jar',
    [string]$GameJar = 'D:\SteamLibrary\steamapps\common\ProjectZomboid\projectzomboid.jar',
    [string]$JdkDir
)

$ErrorActionPreference = 'Stop'
if (-not $JdkDir) {
    $jdkFolder = Join-Path $env:USERPROFILE 'Documents\ChatGPT\PZ - Performance\build\jdk25'
    if (Test-Path -LiteralPath $jdkFolder) {
        $JdkDir = (Get-ChildItem -LiteralPath $jdkFolder -Directory | Select-Object -First 1).FullName
    } else { $JdkDir = $env:JAVA_HOME }
}
$projectRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Build.ps1') -ViewpointJar $ViewpointJar -JdkDir $JdkDir
$buildFolder = (Get-ChildItem -LiteralPath (Join-Path $projectRoot 'build') -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$classes = Join-Path $buildFolder 'classes'
$api = Join-Path $buildFolder 'viewpoint-api.jar'
$tests = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src\test\java') -Filter *.java -Recurse -File)
& (Join-Path $JdkDir 'bin\javac.exe') -encoding UTF-8 -classpath "$api;$classes;$GameJar;$ViewpointJar" -d $classes @($tests.FullName) (Join-Path $PSScriptRoot 'CheckShader.java') (Join-Path $PSScriptRoot 'CheckLua.java') (Join-Path $PSScriptRoot 'CheckPacks.java')
if ($LASTEXITCODE -ne 0) { throw 'Validation compilation failed.' }
& (Join-Path $JdkDir 'bin\java.exe') -classpath "$ViewpointJar;$GameJar;$classes" viewpoint.platform.CheckPacks (Join-Path $projectRoot 'content\mods\ViewpointBathShowerEffects\42\media\viewpoint\shaderpacks')
if ($LASTEXITCODE -ne 0) { throw 'Viewpoint shaderpack loading failed.' }
& (Join-Path $JdkDir 'bin\java.exe') -classpath "$api;$classes" maeiro.bathshower.BridgeTest
if ($LASTEXITCODE -ne 0) { throw 'Bridge tests failed.' }
& (Join-Path $JdkDir 'bin\java.exe') --enable-native-access=ALL-UNNAMED -classpath "$GameJar;$classes" CheckShader (Join-Path $projectRoot 'src\shaders\bath_shower.frag')
if ($LASTEXITCODE -ne 0) { throw 'OpenGL tests failed.' }
& (Join-Path $JdkDir 'bin\java.exe') -classpath "$GameJar;$classes" CheckLua (Join-Path $projectRoot 'content')
if ($LASTEXITCODE -ne 0) { throw 'PZ Lua compilation failed.' }
python (Join-Path $PSScriptRoot 'test_lua.py')
if ($LASTEXITCODE -ne 0) { throw 'Lua behavior tests failed.' }
python (Join-Path $PSScriptRoot 'validate_package.py') -ViewpointJar $ViewpointJar
if ($LASTEXITCODE -ne 0) { throw 'Package checks failed.' }
