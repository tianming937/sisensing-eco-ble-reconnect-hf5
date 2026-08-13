[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaseProject,

    [Parameter(Mandatory = $true)]
    [string]$OutputProject,

    [Parameter(Mandatory = $true)]
    [string]$ApktoolJar,

    [Parameter(Mandatory = $true)]
    [string]$JavaExe,

    [Parameter(Mandatory = $false)]
    [string]$UnsignedApk
)

$ErrorActionPreference = 'Stop'

function Resolve-RequiredPath {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$patchFile = Resolve-RequiredPath (Join-Path $repositoryRoot 'patches\v16.1-hf5-over-v15.patch') 'Patch file'
$base = Resolve-RequiredPath $BaseProject 'v15 base directory'
$apktool = Resolve-RequiredPath $ApktoolJar 'Apktool JAR'
$java = Resolve-RequiredPath $JavaExe 'Java executable'

if (Test-Path -LiteralPath $OutputProject) {
    throw "Output directory already exists; refusing to overwrite: $OutputProject"
}

$requiredFiles = @(
    'apktool.yml',
    'AndroidManifest.xml',
    'smali_classes5\com\sisensing\common\ble\LocalBleService.smali',
    'smali_classes7\p\a.smali',
    'smali_classes8\Aaa.smali'
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $base $relativePath) -PathType Leaf)) {
        throw "The base is not the expected decoded v15 project. Missing: $relativePath"
    }
}

$smaliDirectories = @(
    'smali', 'smali_classes2', 'smali_classes3', 'smali_classes4',
    'smali_classes5', 'smali_classes6', 'smali_classes7', 'smali_classes8'
)
foreach ($directory in $smaliDirectories) {
    if (-not (Test-Path -LiteralPath (Join-Path $base $directory) -PathType Container)) {
        throw "The base is missing a business DEX directory: $directory. Do not apply this patch to the static protected vendor APK."
    }
}

$apktoolText = Get-Content -Raw -LiteralPath (Join-Path $base 'apktool.yml')
if ($apktoolText -notmatch '(?m)^\s*versionCode:\s*31\s*$' -or
    $apktoolText -notmatch '(?m)^\s*versionName:\s*02\.23\.01\.00\s*$') {
    throw 'Base version is not 31 / 02.23.01.00. This patch only supports the project v15 baseline.'
}

$git = (Get-Command git -ErrorAction Stop).Source
& $git -C $base apply --check --ignore-space-change --ignore-whitespace -p1 $patchFile
if ($LASTEXITCODE -ne 0) {
    throw 'Patch preflight failed. The base differs from project v15; nothing was copied or changed.'
}

$outputParent = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputProject))
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Path $outputParent | Out-Null
}

Copy-Item -LiteralPath $base -Destination $OutputProject -Recurse
$output = (Resolve-Path -LiteralPath $OutputProject).Path

# Old local patching sessions may have left backup/reject files beside Smali.
# They are not application sources and must not be copied into a release build.
$outputPrefix = $output.TrimEnd('\') + '\'
$unexpectedResidue = Get-ChildItem -LiteralPath $output -File -Recurse -ErrorAction Stop |
    Where-Object { $_.Name -match '\.(bak|orig|rej)$' }
foreach ($residue in $unexpectedResidue) {
    $resolvedResidue = (Resolve-Path -LiteralPath $residue.FullName).Path
    if (-not $resolvedResidue.StartsWith($outputPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove residue outside the new output tree: $resolvedResidue"
    }
    Remove-Item -LiteralPath $resolvedResidue -Force
}

& $git -C $output apply --ignore-space-change --ignore-whitespace -p1 $patchFile
if ($LASTEXITCODE -ne 0) {
    throw "Patch application failed. Output is preserved for diagnosis: $output"
}

$patchedText = Get-Content -Raw -LiteralPath (Join-Path $output 'apktool.yml')
if ($patchedText -notmatch '(?m)^\s*versionCode:\s*37\s*$' -or
    $patchedText -notmatch '(?m)^\s*versionName:\s*02\.23\.01\.00-v16\.1-hf5\s*$') {
    throw 'Patched version metadata is invalid; build stopped.'
}

if ([string]::IsNullOrWhiteSpace($UnsignedApk)) {
    $UnsignedApk = Join-Path (Split-Path -Parent $output) 'sisensing-v16.1-hf5-unsigned.apk'
}
$unsignedFullPath = [System.IO.Path]::GetFullPath($UnsignedApk)
if (Test-Path -LiteralPath $unsignedFullPath) {
    throw "Unsigned APK already exists; refusing to overwrite: $unsignedFullPath"
}

& $java -jar $apktool build $output --output $unsignedFullPath
if ($LASTEXITCODE -ne 0) {
    throw "Apktool build failed: $LASTEXITCODE"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $unsignedFullPath).Hash
Write-Host 'Build complete (unsigned).'
Write-Host "Project: $output"
Write-Host "APK: $unsignedFullPath"
Write-Host "SHA-256: $hash"
Write-Host 'Next: sign with your own key using scripts\sign-apk.ps1.'
