[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Apk,

    [Parameter(Mandatory = $true)]
    [string]$BuildToolsDir,

    [Parameter(Mandatory = $false)]
    [string]$JavaHome
)

$ErrorActionPreference = 'Stop'

if ($JavaHome) {
    $env:JAVA_HOME = (Resolve-Path -LiteralPath $JavaHome).Path
}

$apkPath = (Resolve-Path -LiteralPath $Apk).Path
$tools = (Resolve-Path -LiteralPath $BuildToolsDir).Path
$zipalign = Join-Path $tools 'zipalign.exe'
$apksigner = Join-Path $tools 'apksigner.bat'
$aapt = Join-Path $tools 'aapt.exe'

foreach ($tool in @($zipalign, $apksigner, $aapt)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Missing Android Build Tools file: $tool"
    }
}

Write-Host '== ZIP alignment =='
& $zipalign -c -v 4 $apkPath | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { throw 'zipalign verification failed.' }

Write-Host '== APK signature =='
& $apksigner verify --verbose --print-certs $apkPath
if ($LASTEXITCODE -ne 0) { throw 'apksigner verification failed.' }

Write-Host '== Package and version =='
$badging = & $aapt dump badging $apkPath
if ($LASTEXITCODE -ne 0) { throw 'aapt could not read the APK.' }
$packageLine = $badging | Select-Object -First 1
Write-Host $packageLine

if ($packageLine -notmatch "name='com\.sisensing\.eco'" -or
    $packageLine -notmatch "versionCode='37'" -or
    $packageLine -notmatch "versionName='02\.23\.01\.00-v16\.1-hf5'") {
    throw 'Package or version metadata does not match v16.1-hf5.'
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash
$size = (Get-Item -LiteralPath $apkPath).Length
Write-Host '== File =='
Write-Host "Path: $apkPath"
Write-Host "Size: $size bytes"
Write-Host "SHA-256: $hash"
