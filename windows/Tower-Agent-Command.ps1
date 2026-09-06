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
