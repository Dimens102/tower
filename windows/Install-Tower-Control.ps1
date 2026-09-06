param([switch]$NoLaunch)

$ErrorActionPreference = 'Stop'
$productName = 'Tower Control'
$productVersion = '0.11.05'
$installDirectory = Join-Path $env:ProgramFiles $productName
$sourceDirectory = $PSScriptRoot
$configDirectory = Join-Path $env:APPDATA 'Tower'
$clientConfigPath = Join-Path $configDirectory 'client.json'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-IsAdministrator)) {
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath)
    )
    if ($NoLaunch) { $arguments += '-NoLaunch' }
    $process = Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList ($arguments -join ' ') `
        -Verb RunAs `
        -Wait `
        -PassThru
    exit $process.ExitCode
}

try {
    if (-not (Test-Path -LiteralPath $clientConfigPath)) {
        throw (
            "Tower configuration was not found at $clientConfigPath. " +
            'Start Tower Control once from the extracted folder, configure its connection, and run the installer again.'
        )
    }
    $clientConfig = Get-Content -LiteralPath $clientConfigPath -Raw |
        ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$clientConfig.server) -or
        [string]::IsNullOrWhiteSpace([string]$clientConfig.token)) {
        throw 'Tower client.json does not contain a server address and API token.'
    }

    New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
    $sourceFull = [IO.Path]::GetFullPath($sourceDirectory).TrimEnd('\')
    $targetFull = [IO.Path]::GetFullPath($installDirectory).TrimEnd('\')
    if (-not $sourceFull.Equals($targetFull, [StringComparison]::OrdinalIgnoreCase)) {
        & "$env:SystemRoot\System32\robocopy.exe" `
            $sourceDirectory `
            $installDirectory `
            /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) {
            throw "Copying Tower Control into Program Files failed with robocopy code $LASTEXITCODE."
        }
    }

    $installedAgent = Join-Path $installDirectory 'Tower-Windows-Agent.ps1'
    if (-not (Test-Path -LiteralPath $installedAgent)) {
        throw "Installed background-agent file is missing: $installedAgent"
    }

    $requestPath = Join-Path $env:TEMP (
        'tower-install-{0}.json' -f [Guid]::NewGuid().ToString('N')
    )
    [ordered]@{
        server = ([string]$clientConfig.server).TrimEnd('/')
        token = [string]$clientConfig.token
        appDirectory = $installDirectory
        userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    } | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $requestPath -Encoding UTF8

    $agentArguments =
        '-NoProfile -ExecutionPolicy Bypass ' +
        "-File `"$installedAgent`" -Mode Install " +
        "-RequestPath `"$requestPath`""
    $agentProcess = Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList $agentArguments `
        -Wait `
        -PassThru
    if ($agentProcess.ExitCode -ne 0) {
        throw "Background-agent installation failed with code $($agentProcess.ExitCode)."
    }

    $programs = [Environment]::GetFolderPath('Programs')
    $shortcutDirectory = Join-Path $programs $productName
    New-Item -ItemType Directory -Path $shortcutDirectory -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut(
        (Join-Path $shortcutDirectory 'Tower Control.lnk')
    )
    $shortcut.TargetPath = "$env:SystemRoot\System32\schtasks.exe"
    $shortcut.Arguments = '/Run /TN "Tower Control - User Logon"'
    $shortcut.WorkingDirectory = $installDirectory
    $iconPath = Join-Path $installDirectory 'assets\tower-icon-tray.ico'
    if (Test-Path -LiteralPath $iconPath) { $shortcut.IconLocation = $iconPath }
    $shortcut.Save()

    $desktopShortcut = $shell.CreateShortcut(
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Tower Control.lnk')
    )
    $desktopShortcut.TargetPath = "$env:SystemRoot\System32\schtasks.exe"
    $desktopShortcut.Arguments = '/Run /TN "Tower Control - User Logon"'
    $desktopShortcut.WorkingDirectory = $installDirectory
    if (Test-Path -LiteralPath $iconPath) {
        $desktopShortcut.IconLocation = $iconPath
    }
    $desktopShortcut.Save()

    $uninstallKey =
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TowerControl'
    New-Item -Path $uninstallKey -Force | Out-Null
    Set-ItemProperty -Path $uninstallKey -Name DisplayName -Value $productName
    Set-ItemProperty -Path $uninstallKey -Name DisplayVersion -Value $productVersion
    Set-ItemProperty -Path $uninstallKey -Name Publisher -Value 'RF Tower Project'
    Set-ItemProperty -Path $uninstallKey -Name InstallLocation -Value $installDirectory
    $uninstaller = Join-Path $installDirectory 'Uninstall-Tower-Control.ps1'
    $uninstallCommand =
        "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstaller`""
    Set-ItemProperty -Path $uninstallKey -Name UninstallString -Value $uninstallCommand
    Set-ItemProperty -Path $uninstallKey -Name NoModify -Type DWord -Value 1
    Set-ItemProperty -Path $uninstallKey -Name NoRepair -Type DWord -Value 1

    Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Tower Control $productVersion was installed successfully.`r`n`r`n" +
        "Application: $installDirectory`r`n" +
        'The background agent is already running.',
        'Tower Control installation', 'OK', 'Information'
    ) | Out-Null

    if (-not $NoLaunch) {
        Start-ScheduledTask -TaskName 'Tower Control - User Logon'
    }
    exit 0
}
catch {
    if ($requestPath) {
        Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
    }
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        'Tower Control installation failed', 'OK', 'Error'
    ) | Out-Null
    exit 1
}
