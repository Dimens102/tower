param([Parameter(Mandatory=$true)][string]$ActionId)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $env:APPDATA 'Tower\client.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw 'Tower Control configuration was not found.' }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$item = @($config.homeActions | Where-Object { [string]$_.id -eq $ActionId }) | Select-Object -First 1
if ($null -eq $item) { throw "Home action no longer exists: $ActionId" }

function Invoke-HomeShortcutPost([string]$path, $body) {
    Invoke-RestMethod -Method Post -Uri "$([string]$config.server)$path" `
        -Headers @{Authorization="Bearer $([string]$config.token)"} `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 50 -Compress) `
        -DisableKeepAlive -TimeoutSec 600
}

switch ([string]$item.kind) {
    'rf_preset' {
        [void](Invoke-HomeShortcutPost '/api/v1/rf/preset' @{
            preset=[int]$item.target; action=[string]$item.action
        })
    }
    'schedule' {
        [void](Invoke-HomeShortcutPost '/api/v1/schedules/run' @{id=[string]$item.target})
    }
    'remote_trigger' {
        [void](Invoke-HomeShortcutPost '/api/v1/control/ir-triggers/run' @{id=[string]$item.target})
    }
    'voice_path' {
        [void](Invoke-HomeShortcutPost '/api/v1/control/actions' @{
            actions=@(@{type='voice_path';path=@($item.path)})
        })
    }
    'ir_command' {
        [void](Invoke-HomeShortcutPost '/api/v1/control/actions' @{
            actions=@(@{type='command';device=[string]$item.target;command=[string]$item.command;transmitters=@($item.transmitters)})
        })
    }
    'script' {
        [void](Invoke-HomeShortcutPost '/api/v1/control/actions' @{
            actions=@(@{type='script';script=[string]$item.target})
        })
    }
    default { throw "Unsupported Home action type: $([string]$item.kind)" }
}
