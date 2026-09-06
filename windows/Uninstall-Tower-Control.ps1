$ErrorActionPreference = 'Stop'
$productName = 'Tower Control'
$installDirectory = Join-Path $env:ProgramFiles $productName

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-IsAdministrator)) {
    $process = Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList (
            '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
        ) `
        -Verb RunAs `
        -Wait `
        -PassThru
    exit $process.ExitCode
}

Add-Type -AssemblyName System.Windows.Forms
$answer = [System.Windows.Forms.MessageBox]::Show(
    'Remove Tower Control, its background agent, startup tasks, and Tower-managed Windows schedules? Personal settings in AppData will be preserved.',
    'Uninstall Tower Control', 'YesNo', 'Warning'
)
if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { exit 0 }

try {
    $scheduleManager = Join-Path $installDirectory 'Tower-Windows-Schedule-Manager.ps1'
    if (Test-Path -LiteralPath $scheduleManager) {
        $process = Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList (
                '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode RemoveAll' -f $scheduleManager
            ) `
            -Wait `
            -PassThru
        if ($process.ExitCode -ne 0) {
            throw "Windows-schedule removal failed with code $($process.ExitCode)."
        }
    }

    $agent = Join-Path $installDirectory 'Tower-Windows-Agent.ps1'
    if (Test-Path -LiteralPath $agent) {
        $process = Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList (
                '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode Remove' -f $agent
            ) `
            -Wait `
            -PassThru
        if ($process.ExitCode -ne 0) {
            throw "Background-agent removal failed with code $($process.ExitCode)."
        }
    }

    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object {
            $_.ProcessId -ne $PID -and
            [string]$_.CommandLine -like "*$installDirectory*Tower-Control.ps1*"
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    $shortcutDirectory = Join-Path `
        ([Environment]::GetFolderPath('Programs')) `
        $productName
    Remove-Item -LiteralPath $shortcutDirectory -Recurse -Force `
        -ErrorAction SilentlyContinue
    Remove-Item `
        -LiteralPath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Tower Control.lnk') `
        -Force `
        -ErrorAction SilentlyContinue
    Remove-Item `
        -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TowerControl' `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    # A separate hidden process removes the installation directory after this
    # running uninstaller has exited. User configuration remains in AppData.
    $escapedDirectory = $installDirectory.Replace("'", "''")
    $cleanup =
        "Start-Sleep -Seconds 2; " +
        "Remove-Item -LiteralPath '$escapedDirectory' -Recurse -Force"
    Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-Command', $cleanup) `
        -WindowStyle Hidden

    [System.Windows.Forms.MessageBox]::Show(
        'Tower Control was removed. Your personal AppData settings were preserved.',
        'Tower Control', 'OK', 'Information'
    ) | Out-Null
    exit 0
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        'Tower Control uninstall failed', 'OK', 'Error'
    ) | Out-Null
    exit 1
}
