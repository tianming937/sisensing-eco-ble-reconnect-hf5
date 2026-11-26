[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Project)
$ErrorActionPreference = 'Stop'

$hf8Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$project = (Resolve-Path -LiteralPath $Project).Path
$sourceManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $hf8Root 'patches\hf8-source-manifest.json') | ConvertFrom-Json

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    Write-Output "PASS: $Message"
}

function Read-Utf8 {
    param([string]$Path)
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Get-MethodBody {
    param([string]$Content, [string]$MethodPattern)
    $pattern = '(?ms)^\.method[^\r\n]*' + $MethodPattern + '\r?\n.*?^\.end method\s*$'
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) { throw "Method not found: $MethodPattern" }
    $match.Value
}

$apktool = Read-Utf8 (Join-Path $project 'apktool.yml')
Assert-True ($apktool -match '(?m)^\s*versionCode:\s+46\s*$') 'versionCode is 46'
Assert-True ($apktool -match '(?m)^\s*versionName:\s+02\.23\.01\.00-v16\.1-hf8\s*$') 'versionName is v16.1-hf8'

$manifest = Join-Path $project 'AndroidManifest.xml'
$manifestText = (Read-Utf8 $manifest).Replace("`r`n", "`n").Replace("`r", "`n")
$sha = [Security.Cryptography.SHA256]::Create()
try { $manifestHash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($manifestText)))).Replace('-', '').ToLowerInvariant() }
finally { $sha.Dispose() }
Assert-True ($manifestHash -eq $sourceManifest.androidManifestSha256) 'Manifest permission/exported surface is unchanged from the project hf6 baseline'

$service = Read-Utf8 (Join-Path $project 'smali_classes5\com\sisensing\common\ble\LocalBleService.smali')
$transportStop = Get-MethodBody $service 'g\(\)V'
Assert-True (-not ($transportStop -match 'iput-boolean[^\r\n]*LocalBleService;->s:Z')) 'internal transport cleanup cannot set the user-pause flag'
$userPause = Get-MethodBody $service 'r1\(Z\)V'
Assert-True ($userPause.Contains('iput-boolean p1, p0, Lcom/sisensing/common/ble/LocalBleService;->s:Z')) 'explicit user pause remains the flag owner'
Assert-True ($userPause.Contains('BleColdStartRestoreHf6;->setManualStop')) 'explicit user pause remains persisted'
Assert-True ($service.Contains('STALE_STATE_IGNORED_MANUAL_STOP_HF8')) 'late GATT state callbacks respect persisted user intent'
Assert-True ($service.Contains('BleForegroundGuardHf8;->start')) 'foreground-service startup is guarded'
Assert-True ($service.Contains('->b1()Z')) 'foreground startup result propagates through b1'
Assert-True ($service.Contains('->X0()Z')) 'foreground startup result propagates through X0'
Assert-True ($service.Contains('FGS_START_COMMAND_ABORT_NOT_STICKY_HF8')) 'rejected foreground startup cannot return START_STICKY'
Assert-True ($service.Contains('BleForegroundGuardHf8;->isReady()Z')) 'onStartCommand observes the onCreate foreground result'
Assert-True (-not ($service -match 'Service;->startForeground\(')) 'LocalBleService has no unguarded direct startForeground call'

$manager = Read-Utf8 (Join-Path $project 'smali_classes5\com\sisensing\common\ble\a.smali')
$managerStop = Get-MethodBody $manager 'g\(\)V'
Assert-True ($managerStop.Contains('LocalBleService;->r1(Z)V')) 'explicit manager stop marks user pause before transport cleanup'

$fgs = Read-Utf8 (Join-Path $project 'smali_classes8\com\sisensing\common\ble\BleForegroundGuardHf8.smali')
foreach ($needle in @(
    'FOREGROUND_SERVICE_CONNECTED_DEVICE',
    'BLUETOOTH_CONNECT',
    'BLUETOOTH_SCAN',
    'UserManager;->isUserUnlocked()Z',
    'FGS_PREREQ_MISSING_HF8',
    'FGS_START_SECURITY_HF8',
    'FGS_START_RUNTIME_HF8',
    'Service;->stopSelf()V'
)) {
    Assert-True ($fgs.Contains($needle)) "foreground guard contains: $needle"
}
Assert-True ($fgs.Contains('const/16 v1, 0x22')) 'connectedDevice prerequisite enforcement is gated to Android 14+'
Assert-True ($fgs.Contains('sput-boolean v0, Lcom/sisensing/common/ble/BleForegroundGuardHf8;->ready:Z')) 'successful startForeground publishes readiness'

$pending = Read-Utf8 (Join-Path $project 'smali_classes8\com\sisensing\common\ble\BlePendingScanHf7.smali')
foreach ($needle in @(
    'android.bluetooth.le.extra.ERROR_CODE',
    'android.bluetooth.le.extra.LIST_SCAN_RESULT',
    'SCAN_TARGET_BATCH_HF8',
    'PENDING_SCAN_ARM_RC_HF8',
    'SCAN_THROTTLE_COOLDOWN_MS_HF8',
    'const-wide/32 v2, 0x1d4c0',
    'const-wide/32 v2, 0x493e0',
    'isTransitionInFlight()Z',
    'onConnectionVerified()V'
)) {
    Assert-True ($pending.Contains($needle)) "ScanLease invariant exists: $needle"
}
$scanStart = Get-MethodBody $pending 'start\(Lcom/sisensing/common/ble/LocalBleService;\)V'
Assert-True ($scanStart.Contains('if-nez v0, :cond_return')) 'PendingIntent ScanLease starts only in disconnected state 0'
Assert-True (([regex]::Matches($scanStart, 'BluetoothLeScanner;->startScan').Count) -eq 1) 'ScanLease has one real startScan site'
Assert-True (-not ($scanStart -match 'BluetoothLeScanner;->stopScan')) 'idempotent start does not stop/restart an active scan'

$wake = Read-Utf8 (Join-Path $project 'smali_classes8\com\sisensing\common\ble\BleWakeSchedulerHf7.smali')
foreach ($needle in @(
    'ALARM_ARM_GEN_HF8',
    'ALARM_STALE_GEN_IGNORED_HF8',
    'ALARM_SCAN_LEASE_HEALTH_HF8',
    'WAKE_IGNORED_PERSISTED_MANUAL_STOP_HF8',
    'nextDueElapsed:J',
    'hf7_generation',
    'BlePendingScanHf7;->handleIntent'
)) {
    Assert-True ($wake.Contains($needle)) "alarm/generation invariant exists: $needle"
}
Assert-True (-not $wake.Contains('setExactAndAllowWhileIdle')) 'scheduler needs no exact-alarm permission'

$handler = Read-Utf8 (Join-Path $project 'smali_classes5\com\sisensing\common\ble\LocalBleService$m.smali')
Assert-True ($handler.Contains('BlePendingScanHf7;->isCoolingDown()Z')) 'vendor scanner is blocked during hard cooldown'
Assert-True ($handler.Contains('BlePendingScanHf7;->isActive()Z')) 'vendor scanner is blocked while the PendingIntent ScanLease owns discovery'

$reconnect = Read-Utf8 (Join-Path $project 'smali_classes8\com\sisensing\common\ble\BleReconnectV16.smali')
foreach ($needle in @(
    'BlePendingScanHf7;->isActive()Z',
    'CONNECTION_VERIFY_TIMEOUT_6M_HF8',
    'CONNECTION_VERIFIED_VALID_DATA_HF8',
    'VALID_ENTITY_ACCEPTED_COUNT_HF8=',
    'SCAN_ERROR_RECOVER_HF8',
    'isTransitionInFlight()Z'
)) {
    Assert-True ($reconnect.Contains($needle)) "reconnect coordinator invariant exists: $needle"
}
Assert-True (-not ($reconnect -match 'iput-boolean[^\r\n]*LocalBleService;->s:Z')) 'internal reconnect recovery never changes user-pause state'
Assert-True ($reconnect.Contains('const-wide/32 v4, 0x57e40')) 'STATE_1 verification window is six minutes'
Assert-True ($reconnect.Contains('const-wide/32 v4, 0xea60')) 'valid-data audit is aggregated at one-minute intervals'

$audit = Read-Utf8 (Join-Path $project 'smali_classes8\com\sisensing\common\ble\BleAuditHf7.smali')
Assert-True ($audit.Contains('ble_audit_hf8_')) 'new diagnostics are isolated in the hf8 audit directory'
Assert-True (-not $audit.Contains('ble_audit_hf7_')) 'hf8 does not append into the hf7 audit stream'
Assert-True (-not ($audit -match '(?i)const-string[^\r\n]*"[^"]*(user_token|followedUserId|deviceName|mac|glucose)[^"]*"')) 'audit persists no account, target, MAC, or glucose identifier'

# Preserve the two user-visible hf6 repairs and the hf5 unknown-algorithm guard.
$profile = Read-Utf8 (Join-Path $project 'smali_classes6\com\sisensing\personalcenter\activity\PersonalDataEditActivity.smali')
Assert-True ($profile.Contains('if-eqz v0, :setup_titlebar_listener')) 'profile edit keeps the TitleBar null guard'
$share = Read-Utf8 (Join-Path $project 'smali_classes8\com\sisensing\personalcenter\share\ShareRequestGuardHf6.smali')
Assert-True ($share.Contains('SHARE_AUTH_MISSING_HF6')) 'blood-glucose sharing keeps the auth guard'
$algorithm = Read-Utf8 (Join-Path $project 'smali_classes5\c9.smali')
Assert-True ($algorithm.Contains('ALGORITHM_UNSUPPORTED_OR_VERIFY_FAILED')) 'unknown probe algorithms remain fail-closed'
Assert-True ($algorithm.Contains('.catch Ljava/lang/Throwable;')) 'known algorithm preflight contains VerifyError and native-wrapper failures'

Write-Output 'HF8_STATIC_VERIFY_RESULT=PASS'
