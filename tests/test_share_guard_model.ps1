$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    Write-Output "PASS: $Message"
}

class ShareGuardModel {
    [string]$Token = ''
    [string]$SeenToken = ''
    [bool]$InFlight = $false
    [long]$StartedAt = 0
    [long]$NextAllowed = 0
    [int]$Begins = 0
    [int]$Merged = 0
    [int]$AuthMissing = 0
    [int]$StaleResets = 0

    [bool] TryBegin([long]$Now) {
        if ([string]::IsNullOrEmpty($this.Token)) {
            $this.InFlight = $false
            $this.AuthMissing++
            return $false
        }
        if ($this.SeenToken -ne $this.Token) {
            $this.SeenToken = $this.Token
            $this.InFlight = $false
            $this.NextAllowed = 0
        }
        if ($this.InFlight) {
            if (($Now - $this.StartedAt) -lt 30000) {
                $this.Merged++
                return $false
            }
            $this.InFlight = $false
            $this.StaleResets++
        }
        if ($Now -lt $this.NextAllowed) {
            return $false
        }
        $this.InFlight = $true
        $this.StartedAt = $Now
        $this.Begins++
        return $true
    }

    [void] Success() {
        $this.InFlight = $false
        $this.NextAllowed = 0
    }

    [void] NetworkFailure([long]$Now) {
        $this.InFlight = $false
        $this.NextAllowed = $Now + 15000
    }

    [void] BusinessFailure([long]$Now) {
        $this.InFlight = $false
        $this.NextAllowed = $Now + 30000
    }
}

$g = [ShareGuardModel]::new()
Assert-True (-not $g.TryBegin(1000)) 'missing token blocks the request'
Assert-True ($g.AuthMissing -eq 1) 'missing token is observable without sending a request'

$g.Token = 'session-A'
Assert-True ($g.TryBegin(2000)) 'valid session starts the first request'
Assert-True (-not $g.TryBegin(2100)) 'duplicate resume request is merged'
Assert-True ($g.Merged -eq 1) 'single-flight merge is counted'

$g.Success()
Assert-True ($g.TryBegin(3000)) 'success releases the request lock'
$g.NetworkFailure(3100)
Assert-True (-not $g.TryBegin(10000)) 'network failure applies bounded cooldown'
Assert-True ($g.TryBegin(18100)) 'network cooldown eventually allows retry'

$g.BusinessFailure(18200)
Assert-True (-not $g.TryBegin(30000)) 'business failure applies bounded cooldown'
$g.Token = 'session-B'
Assert-True ($g.TryBegin(30100)) 'a changed login session clears stale cooldown'

$g.InFlight = $true
$g.StartedAt = 1000
Assert-True ($g.TryBegin(40000)) 'a callback lost for 30 seconds is reset'
Assert-True ($g.StaleResets -eq 1) 'stale single-flight reset is observable'

Write-Output 'SHARE_GUARD_MODEL_RESULT=PASS'
