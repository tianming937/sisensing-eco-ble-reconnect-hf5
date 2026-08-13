[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UnsignedApk,

    [Parameter(Mandatory = $true)]
    [string]$OutputApk,

    [Parameter(Mandatory = $true)]
    [string]$Keystore,

    [Parameter(Mandatory = $true)]
    [string]$Alias,

    [Parameter(Mandatory = $true)]
    [string]$BuildToolsDir,

    [Parameter(Mandatory = $false)]
    [string]$JavaHome
)

$ErrorActionPreference = 'Stop'

if ($JavaHome) {
    $resolvedJavaHome = (Resolve-Path -LiteralPath $JavaHome).Path
    $env:JAVA_HOME = $resolvedJavaHome
}

$unsigned = (Resolve-Path -LiteralPath $UnsignedApk).Path
$keystorePath = (Resolve-Path -LiteralPath $Keystore).Path
$tools = (Resolve-Path -LiteralPath $BuildToolsDir).Path
$zipalign = Join-Path $tools 'zipalign.exe'
$apksigner = Join-Path $tools 'apksigner.bat'

foreach ($tool in @($zipalign, $apksigner)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Missing Android Build Tools file: $tool"
    }
}

$output = [System.IO.Path]::GetFullPath($OutputApk)
if (Test-Path -LiteralPath $output) {
    throw "Output APK already exists; refusing to overwrite: $output"
}

$outputDirectory = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$aligned = Join-Path $outputDirectory (([System.IO.Path]::GetFileNameWithoutExtension($output)) + '.aligned-unsigned.apk')
if (Test-Path -LiteralPath $aligned) {
    throw "Aligned intermediate already exists; refusing to overwrite: $aligned"
}

& $zipalign -p 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) {
    throw "zipalign failed: $LASTEXITCODE"
}

Write-Host 'apksigner will securely prompt for keystore/key passwords; they are not passed as script arguments.'
& $apksigner sign --ks $keystorePath --ks-key-alias $Alias --out $output $aligned
if ($LASTEXITCODE -ne 0) {
    throw "APK signing failed: $LASTEXITCODE. The aligned intermediate remains at $aligned"
}

& $zipalign -c -v 4 $output | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) {
    throw 'Post-signing zipalign verification failed.'
}

& $apksigner verify --verbose --print-certs $output
if ($LASTEXITCODE -ne 0) {
    throw 'apksigner verification failed.'
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash
Write-Host "Signed APK: $output"
Write-Host "SHA-256: $hash"
Write-Host "Aligned intermediate: $aligned"
