[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseProject,
    [Parameter(Mandatory = $true)][string]$OutputProject,
    [string]$ApktoolJar,
    [string]$JavaExe,
    [string]$UnsignedApk,
    [switch]$PatchOnly
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$patch = Join-Path $repo 'patches\v16.1-hf8-over-hf6.patch'
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repo 'patches\hf8-source-manifest.json') | ConvertFrom-Json
$base = (Resolve-Path -LiteralPath $BaseProject).Path.TrimEnd('\', '/')
$output = [IO.Path]::GetFullPath($OutputProject).TrimEnd('\', '/')

function Get-TextHash([string]$Path) {
    $value = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).Replace("`r`n", "`n").Replace("`r", "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-ChildPath([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[/\\])\.\.([/\\]|$)') { throw "Unsafe relative path: $Relative" }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $full.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes project: $Relative"
    }
    return $full
}

if (Test-Path -LiteralPath $output) { throw 'OutputProject already exists; nothing will be overwritten.' }
if ($output.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $base.StartsWith($output + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Input and output must be separate, non-nested trees.' }
if ($manifest.schemaVersion -ne 1) { throw 'Unsupported patch manifest schema.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash -ne $manifest.patchSha256) { throw 'Patch SHA-256 mismatch.' }
$yaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $base 'apktool.yml')
if ($yaml -notmatch '(?m)^\s*versionCode:\s*44\s*$' -or $yaml -notmatch '(?m)^\s*versionName:\s*02\.23\.01\.00-v16\.1-hf6\s*$') {
    throw 'Expected the project hf6/code44 source baseline, not hf5 or a freshly decoded vendor APK.'
}
if ((Get-TextHash (Join-Path $base 'AndroidManifest.xml')) -ne $manifest.androidManifestSha256) { throw 'Baseline Manifest differs.' }
foreach ($entry in $manifest.files) {
    $path = Get-ChildPath $base $entry.path
    if ($null -eq $entry.beforeSha256) {
        if (Test-Path -LiteralPath $path) { throw "New class already exists in baseline: $($entry.path)" }
    } elseif (-not (Test-Path -LiteralPath $path) -or (Get-TextHash $path) -ne $entry.beforeSha256) {
        throw "Baseline source fingerprint differs: $($entry.path)"
    }
}
foreach ($entry in $manifest.compatibilityCopies) {
    $source = Get-ChildPath $base $entry.source
    $null = Get-ChildPath $output $entry.target
    if (-not (Test-Path -LiteralPath $source) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne $entry.sha256) {
        throw "Missing/different compatibility metadata in baseline: $($entry.source)"
    }
}
$git = (Get-Command git -ErrorAction Stop).Source
& $git -C $base apply --check --ignore-space-change --ignore-whitespace -p1 $patch
if ($LASTEXITCODE -ne 0) { throw 'Patch preflight failed; baseline was not modified.' }

if (-not $PatchOnly) {
    if (-not $JavaExe -or -not $ApktoolJar) { throw 'Provide JavaExe and ApktoolJar, or use -PatchOnly.' }
    $java = (Resolve-Path -LiteralPath $JavaExe).Path
    $apktool = (Resolve-Path -LiteralPath $ApktoolJar).Path
    if (-not $UnsignedApk) { $UnsignedApk = Join-Path (Split-Path -Parent $output) 'sisensing-eco-v16.1-hf8-code46-unsigned.apk' }
    $unsigned = [IO.Path]::GetFullPath($UnsignedApk)
    if (Test-Path -LiteralPath $unsigned) { throw 'UnsignedApk already exists; refusing to overwrite.' }
    $toolVersion = & $java -jar $apktool version
    if ($LASTEXITCODE -ne 0 -or (($toolVersion -join '').Trim() -ne '2.12.0')) { throw 'This hf8 workflow was tested with Apktool 2.12.0.' }
}

# Copy only source inputs. No old build cache, private .git, or original signatures.
$inputs = @('AndroidManifest.xml', 'apktool.yml', 'assets', 'kotlin', 'lib', 'META-INF', 'res', 'unknown',
    'smali', 'smali_classes2', 'smali_classes3', 'smali_classes4', 'smali_classes5', 'smali_classes6', 'smali_classes7', 'smali_classes8')
foreach ($name in $inputs) {
    $path = Join-Path $base $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing source input: $name" }
    $linked = @(Get-Item -LiteralPath $path; if (Test-Path -LiteralPath $path -PathType Container) { Get-ChildItem -LiteralPath $path -Recurse -Force }) |
        Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }
    if ($linked) { throw "Refusing a source tree containing junctions/symlinks: $name" }
}
New-Item -ItemType Directory -Path $output -Force | Out-Null
foreach ($name in $inputs) { Copy-Item -LiteralPath (Join-Path $base $name) -Destination (Join-Path $output $name) -Recurse }
& $git -C $output apply --ignore-space-change --ignore-whitespace -p1 $patch
if ($LASTEXITCODE -ne 0) { throw "Patch failed; new output preserved for inspection: $output" }
foreach ($entry in $manifest.compatibilityCopies) {
    $destination = Get-ChildPath $output $entry.target
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Get-ChildPath $base $entry.source) -Destination $destination
}
foreach ($entry in $manifest.files) {
    if ((Get-TextHash (Get-ChildPath $output $entry.path)) -ne $entry.afterSha256) { throw "Patched source fingerprint differs: $($entry.path)" }
}
Write-Output 'HF8_PATCH_RESULT=PASS'
if ($PatchOnly) { Write-Output "Project: $output"; return }
New-Item -ItemType Directory -Path (Split-Path -Parent $unsigned) -Force | Out-Null
& $java -jar $apktool build $output --output $unsigned
if ($LASTEXITCODE -ne 0) { throw "Apktool build failed: $LASTEXITCODE" }
Get-FileHash -Algorithm SHA256 -LiteralPath $unsigned
Write-Output 'HF8_BUILD_RESULT=PASS (unsigned; use your own signing key)'
