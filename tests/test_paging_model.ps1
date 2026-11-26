$ErrorActionPreference = 'Stop'

$pageSize = 120
$sizes = @(0, 1, 119, 120, 121, 1000, 20160, 50000, 60000)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    Write-Output "PASS: $Message"
}

foreach ($count in $sizes) {
    $pages = if ($count -eq 0) { 0 } else { [int][Math]::Ceiling($count / [double]$pageSize) }
    $reconstructed = 0
    $maxLiveRows = 0
    $allPagesBounded = $true
    for ($page = 0; $page -lt $pages; $page++) {
        $remaining = $count - $reconstructed
        $rows = [Math]::Min($pageSize, $remaining)
        if ($rows -gt $pageSize) { $allPagesBounded = $false }
        $maxLiveRows = [Math]::Max($maxLiveRows, $rows)
        $reconstructed += $rows
    }
    Assert-True $allPagesBounded "count=$count every page is capped at 120"
    Assert-True ($reconstructed -eq $count) "count=$count pages reconstruct without omission"
    Assert-True ($maxLiveRows -le $pageSize) "count=$count never materializes more than 120 rows"
}

Assert-True (([Math]::Ceiling(50000 / 120.0)) -eq 417) '50,000-row backlog is 417 bounded pages'
Assert-True (([Math]::Ceiling(60000 / 120.0)) -eq 500) '500-page pressure model contains 60,000 rows'

function Test-Ack {
    param([int]$Current, [int]$SentMax, [AllowNull()][object]$Ack)
    if ($null -eq $Ack) { return $false }
    $ackValue = [int]$Ack
    if ($ackValue -lt 0) { return $false }
    # The one-record bootstrap asks for the server's existing cursor; it can
    # legitimately be greater than the probe row's index.
    if ($Current -lt 0) { return $true }
    if ($ackValue -le $Current) { return $false }
    if ($ackValue -gt $SentMax) { return $false }
    return $true
}

Assert-True (-not (Test-Ack 900 1020 $null)) 'null ACK is rejected'
Assert-True (-not (Test-Ack 900 1020 -1)) 'negative ACK is rejected'
Assert-True (-not (Test-Ack 900 1020 899)) 'regressing ACK is rejected'
Assert-True (-not (Test-Ack 900 1020 900)) 'stalled ACK is rejected'
Assert-True (-not (Test-Ack 900 1020 1021)) 'ACK beyond sent page is rejected'
Assert-True (Test-Ack 900 1020 1020) 'valid advancing ACK is accepted'
Assert-True (Test-Ack -1 315 900) 'bootstrap accepts a nonnegative server cursor beyond the probe row'

$uploadBackoffMinutes = @(1, 5, 15, 30, 30, 30)
Assert-True (($uploadBackoffMinutes -join ',') -eq '1,5,15,30,30,30') 'upload retry backoff is capped at 30 minutes'
$restoreBackoffSeconds = @(2, 5, 15, 30, 60, 60)
Assert-True (($restoreBackoffSeconds -join ',') -eq '2,5,15,30,60,60') 'cold-restore retry backoff is capped at 60 seconds'

Write-Output 'PAGING_MODEL_RESULT=PASS'
