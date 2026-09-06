# Tower Control Windows installation

## MSI installation

Run `installer\windows\output\Tower-Control-0.11.05-x64.msi` and accept the UAC
prompt. It installs Tower Control in `C:\Program Files\Tower Control`, creates
desktop and Start-menu shortcuts, and registers a normal Windows Installed Apps
entry.

If `%APPDATA%\Tower\client.json` already contains the Tower address and token,
the MSI also configures and starts the background agent automatically. On a new
PC, start Tower Control, configure the connection, and use **Settings > Install
/ Repair** once.

Personal settings in `%APPDATA%\Tower` are preserved during upgrades and
uninstall.

## Development/recovery installation

1. Start Tower Control once from the extracted folder so `%APPDATA%\Tower\client.json`
   contains the Tower address and API token.
2. Close Tower Control.
3. Double-click `Install-Tower-Control.cmd` and accept the UAC prompt.

The installer places the application in `C:\Program Files\Tower Control`, starts
the background agent immediately, registers the GUI for delayed user-logon
startup, adds Start-menu and desktop shortcuts, and creates a Windows uninstall
entry. Both shortcuts start the registered GUI task without opening a console.

During development, updated files can be copied directly into the Program Files
folder. Restart `Tower Background Agent` in Task Scheduler after changing its
script; close and start Tower Control again after changing GUI scripts.

Personal settings in `%APPDATA%\Tower` are retained during updates and uninstall.
The protected agent connection is stored in `C:\ProgramData\Tower\agent.json`.
