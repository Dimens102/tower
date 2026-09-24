param(
    [ValidateSet('GET', 'POST')]
    [string]$Method = 'POST',
    [string]$Path = '',
    [string]$BodyJson = '{}',
    [string]$ScheduleId = ''
)

$ErrorActionPreference = 'Stop'
if (-not [string]::IsNullOrWhiteSpace($ScheduleId)) {
    if ($ScheduleId -notmatch '^[A-Fa-f0-9]{32}$') {
        throw 'Invalid Tower schedule ID.'
    }
    $Method = 'POST'
    $Path = '/api/v1/schedules/run'
    $BodyJson = @{ id = $ScheduleId } | ConvertTo-Json -Compress
}
if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'A Tower API path or schedule ID is required.'
}
if ($Path -notmatch '^/api/v1/[A-Za-z0-9_./-]+$') {
    throw "Invalid Tower API path: $Path"
}

$towerRoot = Join-Path $env:ProgramData 'Tower'
$queuePath = Join-Path $towerRoot 'Queue'
New-Item -ItemType Directory -Path $queuePath -Force | Out-Null

$body = $null
if ($Method -eq 'POST') {
    $body = ConvertFrom-Json -InputObject $BodyJson
}

# Windows logoff and power-off leave only a short execution window. Try the
# request synchronously with the protected SYSTEM agent configuration first;
# the normal disk queue remains the fallback for temporary Tower outages.
$agentConfigPath = Join-Path $towerRoot 'agent.json'
if (Test-Path -LiteralPath $agentConfigPath) {
    try {
        $agentConfig = Get-Content -LiteralPath $agentConfigPath -Raw | ConvertFrom-Json
        $request = @{
            Method = $Method
            Uri = "$([string]$agentConfig.server)$Path"
            Headers = @{ Authorization = "Bearer $([string]$agentConfig.token)" }
            DisableKeepAlive = $true
            TimeoutSec = 10
        }
        if ($Method -eq 'POST') {
            $request.ContentType = 'application/json'
            $request.Body = $BodyJson
        }
        [void](Invoke-RestMethod @request)
        exit 0
    }
    catch {
        # Queue below so the background agent can retry after connectivity returns.
    }
}
$id = [Guid]::NewGuid().ToString('N')
$temporary = Join-Path $queuePath "$id.tmp"
$destination = Join-Path $queuePath "$id.json"
[ordered]@{
    id = $id
    createdUtc = [DateTime]::UtcNow.ToString('o')
    method = $Method
    path = $Path
    body = $body
} | ConvertTo-Json -Depth 50 |
    Set-Content -LiteralPath $temporary -Encoding UTF8
Move-Item -LiteralPath $temporary -Destination $destination -Force
