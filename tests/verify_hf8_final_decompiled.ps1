[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$DecodedProject)
$ErrorActionPreference = 'Stop'

$decoded = (Resolve-Path -LiteralPath $DecodedProject).Path

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
    if (-not $match.Success) { throw "Method not found in final APK: $MethodPattern" }
    $match.Value
}

Assert-True (Test-Path -LiteralPath $decoded) 'final code46 APK was decompiled'
$partitions = @(Get-ChildItem -LiteralPath $decoded -Directory -Filter 'smali*')
Assert-True ($partitions.Count -eq 8) 'final APK contains eight DEX partitions'

$apktool = Read-Utf8 (Join-Path $decoded 'apktool.yml')
Assert-True ($apktool -match '(?m)^\s*versionCode:\s+46\s*$') 'final APK versionCode is 46'
Assert-True ($apktool -match '(?m)^\s*versionName:\s+02\.23\.01\.00-v16\.1-hf8\s*$') 'final APK versionName is v16.1-hf8'

$builtins = @(Get-ChildItem -LiteralPath (Join-Path $decoded 'unknown\kotlin') -Recurse -File -Filter '*.kotlin_builtins')
$providers = @(Get-ChildItem -LiteralPath (Join-Path $decoded 'unknown\META-INF\services') -File)
Assert-True ($builtins.Count -eq 7) 'final APK preserves seven Kotlin built-ins files'
Assert-True ($providers.Count -eq 8) 'final APK preserves eight META-INF service providers'

$service = Read-Utf8 (Join-Path $decoded 'smali_classes5\com\sisensing\common\ble\LocalBleService.smali')
$transportStop = Get-MethodBody $service 'g\(\)V'
Assert-True (-not ($transportStop -match 'iput-boolean[^\r\n]*LocalBleService;->s:Z')) 'final internal cleanup cannot set user pause'
Assert-True ($service.Contains('BleForegroundGuardHf8;->start')) 'final service uses the FGS guard'
Assert-True ($service.Contains('->b1()Z') -and $service.Contains('->X0()Z')) 'final service propagates failed FGS startup to onCreate'
Assert-True ($service.Contains('FGS_START_COMMAND_ABORT_NOT_STICKY_HF8')) 'final service cannot remain START_STICKY after foreground rejection'
Assert-True ($service.Contains('STALE_STATE_IGNORED_MANUAL_STOP_HF8')) 'final service rejects late state callbacks after user pause'

$fgs = Read-Utf8 (Join-Path $decoded 'smali_classes8\com\sisensing\common\ble\BleForegroundGuardHf8.smali')
Assert-True ($fgs.Contains('FGS_START_SECURITY_HF8')) 'final APK contains SecurityException containment'
Assert-True ($fgs.Contains('FOREGROUND_SERVICE_CONNECTED_DEVICE')) 'final APK validates connectedDevice prerequisites'
Assert-True ($fgs.Contains('const/16 v1, 0x22')) 'final APK gates type prerequisites to Android 14+'
Assert-True ($fgs.Contains('isReady()Z')) 'final APK exposes foreground startup readiness'

$pending = Read-Utf8 (Join-Path $decoded 'smali_classes8\com\sisensing\common\ble\BlePendingScanHf7.smali')
foreach ($needle in @(
    'android.bluetooth.le.extra.ERROR_CODE',
    'android.bluetooth.le.extra.LIST_SCAN_RESULT',
    'PENDING_SCAN_ARM_RC_HF8',
    'SCAN_THROTTLE_COOLDOWN_MS_HF8',
    'const-wide/32 v2, 0x1d4c0',
    'const-wide/32 v2, 0x493e0',
    'isTransitionInFlight()Z'
)) {
    Assert-True ($pending.Contains($needle)) "final ScanLease contains: $needle"
}
$scanStart = Get-MethodBody $pending 'start\(Lcom/sisensing/common/ble/LocalBleService;\)V'
Assert-True (([regex]::Matches($scanStart, 'BluetoothLeScanner;->startScan').Count) -eq 1) 'final ScanLease contains one startScan site'
Assert-True (-not $scanStart.Contains('BluetoothLeScanner;->stopScan')) 'final idempotent start does not churn scan registration'

$wake = Read-Utf8 (Join-Path $decoded 'smali_classes8\com\sisensing\common\ble\BleWakeSchedulerHf7.smali')
foreach ($needle in @('ALARM_STALE_GEN_IGNORED_HF8','ALARM_SCAN_LEASE_HEALTH_HF8','WAKE_IGNORED_PERSISTED_MANUAL_STOP_HF8','nextDueElapsed:J')) {
    Assert-True ($wake.Contains($needle)) "final wake coordinator contains: $needle"
}

$handler = Read-Utf8 (Join-Path $decoded 'smali_classes5\com\sisensing\common\ble\LocalBleService$m.smali')
Assert-True ($handler.Contains('BlePendingScanHf7;->isActive()Z')) 'final Handler cannot overlap a healthy ScanLease'
Assert-True ($handler.Contains('BlePendingScanHf7;->isCoolingDown()Z')) 'final Handler cannot bypass scanner cooldown'

$reconnect = Read-Utf8 (Join-Path $decoded 'smali_classes8\com\sisensing\common\ble\BleReconnectV16.smali')
foreach ($needle in @('CONNECTION_VERIFY_TIMEOUT_6M_HF8','CONNECTION_VERIFIED_VALID_DATA_HF8','VALID_ENTITY_ACCEPTED_COUNT_HF8=','SCAN_ERROR_RECOVER_HF8')) {
    Assert-True ($reconnect.Contains($needle)) "final reconnect verification contains: $needle"
}
Assert-True (-not ($reconnect -match 'iput-boolean[^\r\n]*LocalBleService;->s:Z')) 'final internal reconnect paths never mutate user pause'

$audit = Read-Utf8 (Join-Path $decoded 'smali_classes8\com\sisensing\common\ble\BleAuditHf7.smali')
Assert-True ($audit.Contains('ble_audit_hf8_')) 'final APK writes a separate hf8 audit stream'
Assert-True (-not $audit.Contains('ble_audit_hf7_')) 'final APK does not append to hf7 audit files'

$profile = Read-Utf8 (Join-Path $decoded 'smali_classes6\com\sisensing\personalcenter\activity\PersonalDataEditActivity.smali')
$profileInit = Get-MethodBody $profile 'Q0\(\)V'
Assert-True ($profileInit.Contains('TitleBar;->getRightCustomView()Landroid/view/View;')) 'final profile editor still reads the optional right custom view'
Assert-True (([regex]::Matches($profileInit, '(?m)^\s*if-eqz\s+')).Count -ge 2) 'final APK preserves both profile-edit null guards'
$share = Read-Utf8 (Join-Path $decoded 'smali_classes8\com\sisensing\personalcenter\share\ShareRequestGuardHf6.smali')
Assert-True ($share.Contains('SHARE_AUTH_MISSING_HF6')) 'final APK preserves sharing auth guard'
$algorithm = Read-Utf8 (Join-Path $decoded 'smali_classes5\c9.smali')
Assert-True ($algorithm.Contains('ALGORITHM_UNSUPPORTED_OR_VERIFY_FAILED')) 'final APK preserves unknown-algorithm fail-closed behavior'

Write-Output 'HF8_FINAL_DECOMPILED_VERIFY_RESULT=PASS'
