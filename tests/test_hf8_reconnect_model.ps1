$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    Write-Output "PASS: $Message"
}

function New-State {
    [pscustomobject]@{
        UserPaused = $false
        TransportStopping = $false
        ScanLeaseActive = $false
        ScanStarts = 0
        VendorConnects = 0
        Generation = 1
        RetryAttempt = 3
        Connected = $false
        Verified = $false
        CooldownUntil = 0L
        ThrottleCount = 0
    }
}

function Ensure-ScanLease($s, [long]$now) {
    if ($s.UserPaused -or $s.Connected -or $now -lt $s.CooldownUntil) { return }
    if ($s.ScanLeaseActive) { return }
    $s.ScanLeaseActive = $true
    $s.ScanStarts++
}

function Alarm-Tick($s, [long]$now) {
    if ($s.UserPaused) { return 'paused' }
    if ($now -lt $s.CooldownUntil) { return 'cooldown' }
    Ensure-ScanLease $s $now
    if ($s.ScanLeaseActive) { return 'lease-health' }
    $s.VendorConnects++
    return 'vendor-fallback'
}

function Target-Seen($s) {
    if ($s.UserPaused -or -not $s.ScanLeaseActive) { return }
    $s.ScanLeaseActive = $false
    $s.VendorConnects++
}

function Scan-Error6($s, [long]$now) {
    $s.ScanLeaseActive = $false
    $s.ThrottleCount = [Math]::Min(2, $s.ThrottleCount + 1)
    $delay = if ($s.ThrottleCount -eq 1) { 120000L } else { 300000L }
    $s.CooldownUntil = $now + $delay
    $delay
}

function Internal-Transport-Stop($s) {
    $s.TransportStopping = $true
    # Deliberately does not mutate UserPaused.
}

function User-Pause($s) {
    $s.UserPaused = $true
    $s.ScanLeaseActive = $false
    $s.Generation++
}

function Handle-AlarmGeneration($s, [int]$generation) {
    if ($generation -ne $s.Generation) { return 'stale' }
    'accepted'
}

function State1($s) {
    $s.Connected = $true
    $s.Verified = $false
    # retryAttempt is intentionally retained until valid algorithm data.
}

function Valid-Data($s) {
    if (-not $s.Connected) { return }
    $s.Verified = $true
    $s.RetryAttempt = 0
    $s.ThrottleCount = 0
    $s.CooldownUntil = 0L
}

$s = New-State
1..100 | ForEach-Object { Ensure-ScanLease $s 0 }
Assert-True ($s.ScanStarts -eq 1) '100 scheduler calls create one idempotent PendingIntent ScanLease'

1..20 | ForEach-Object { $result = Alarm-Tick $s ($_ * 120000L); Assert-True ($result -eq 'lease-health') 'alarm remains a lease health check' }
Assert-True ($s.VendorConnects -eq 0) 'healthy ScanLease never overlaps the vendor scanner'
Assert-True ($s.ScanStarts -eq 1) 'health alarms do not stop/start the scan lease'

Target-Seen $s
Assert-True (-not $s.ScanLeaseActive -and $s.VendorConnects -eq 1) 'real target discovery transfers ownership once to vendor connect'

$s = New-State
Ensure-ScanLease $s 0
$first = Scan-Error6 $s 1000
Assert-True ($first -eq 120000 -and $s.CooldownUntil -eq 121000) 'first Android status=6 enforces a 120-second hard cooldown'
Ensure-ScanLease $s 120999
Assert-True ($s.ScanStarts -eq 1) 'manual/alarm scan cannot bypass the first cooldown'
$second = Scan-Error6 $s 121000
Assert-True ($second -eq 300000 -and $s.CooldownUntil -eq 421000) 'repeated status=6 escalates to a 300-second cooldown'

$s = New-State
Internal-Transport-Stop $s
Assert-True (-not $s.UserPaused) 'internal GATT cleanup cannot become a permanent user pause'
User-Pause $s
Assert-True ($s.UserPaused -and -not $s.ScanLeaseActive) 'explicit user pause remains fail-closed'

$s = New-State
$old = $s.Generation
User-Pause $s
Assert-True ((Handle-AlarmGeneration $s $old) -eq 'stale') 'an in-flight alarm from the old generation is ignored'

$s = New-State
State1 $s
Assert-True ($s.Connected -and -not $s.Verified -and $s.RetryAttempt -eq 3) 'STATE_1 alone is provisional and does not clear retry history'
Valid-Data $s
Assert-True ($s.Verified -and $s.RetryAttempt -eq 0) 'validated algorithm data commits connection success'

$s = New-State
Valid-Data $s
Assert-True (-not $s.Verified -and $s.RetryAttempt -eq 3) 'late data outside CONNECTED cannot verify a stale generation'

Write-Output 'HF8_RECONNECT_MODEL_RESULT=PASS'
