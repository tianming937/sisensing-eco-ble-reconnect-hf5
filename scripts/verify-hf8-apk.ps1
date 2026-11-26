[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [Parameter(Mandatory = $true)][string]$BuildToolsDir,
    [string]$JavaHome,
    [switch]$AllowRebuilt
)
$ErrorActionPreference = 'Stop'
if ($JavaHome) { $env:JAVA_HOME = (Resolve-Path -LiteralPath $JavaHome).Path }
$apkPath = (Resolve-Path -LiteralPath $Apk).Path
$sdkTools = (Resolve-Path -LiteralPath $BuildToolsDir).Path
$zipalign = Join-Path $sdkTools 'zipalign.exe'
$apksigner = Join-Path $sdkTools 'apksigner.bat'
$aapt = Join-Path $sdkTools 'aapt2.exe'
foreach ($tool in @($zipalign, $apksigner, $aapt)) { if (-not (Test-Path -LiteralPath $tool)) { throw "Missing tool: $tool" } }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash.ToLowerInvariant()
$expected = '538c786914bbbf6d514280701cbb26afe2da4ea5346e98cad2a65ad984aa1797'
if (-not $AllowRebuilt -and $hash -ne $expected) { throw 'Not the published hf8-r2/code46 APK: SHA-256 mismatch.' }
& $zipalign -c 4 $apkPath
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed.' }
$signing = @(& $apksigner verify --verbose --print-certs $apkPath 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'apksigner failed.' }
$signing | ForEach-Object { Write-Output $_ }
if (-not $AllowRebuilt -and ($signing -join "`n") -notmatch 'efc23cb150fac98a6b45d93fc0914794b778e542fed6ff7c21925eab824dba8c') { throw 'Published signing certificate mismatch.' }
$badging = @(& $aapt dump badging $apkPath)
if ($LASTEXITCODE -ne 0) { throw 'aapt2 failed.' }
$package = $badging | Select-Object -First 1
if ($package -notmatch "name='com\.sisensing\.eco'" -or $package -notmatch "versionCode='46'" -or $package -notmatch "versionName='02\.23\.01\.00-v16\.1-hf8'") { throw 'Wrong package/version.' }
Write-Output $package
Write-Output "SHA256=$hash"
Write-Output "BYTES=$((Get-Item -LiteralPath $apkPath).Length)"
Write-Output 'HF8_APK_VERIFY_RESULT=PASS'
if ($AllowRebuilt) { Write-Warning 'Rebuilt artifact: original release hash/signing identity were intentionally not required.' }
