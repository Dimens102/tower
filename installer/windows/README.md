# Tower Control MSI

This directory contains the reproducible Windows installer definition. The
editable application remains in `windows/`; the MSI bundles that directory at
build time.

## Build on Debian/Ubuntu/WSL

```bash
sudo apt update
sudo apt install -y python3 wixl
cd ~/Development/rf-tower
bash installer/windows/build-msi.sh
```

Output: `installer/windows/output/Tower-Control-0.11.05-x64.msi`

## Installation behavior

- Installs per-machine into `C:\Program Files\Tower Control`.
- Creates clean desktop and Start-menu shortcuts.
- Registers Tower Control with Windows Installed Apps.
- Preserves `%APPDATA%\Tower` personal settings during upgrades and uninstall.
- If `%APPDATA%\Tower\client.json` already contains a server and token, the
  background agent and both startup tasks are installed automatically.
- If no valid connection exists yet, Tower Control is still installed. Start
  it, configure the Tower connection, then use **Settings > Install / Repair**
  to activate the background agent.
- Windows-triggered Control schedules are installed under
  `\RF Tower\Schedules` in Task Scheduler. Removing Tower Control also removes
  those managed tasks.

The MSI is currently unsigned, so Windows may show an Unknown Publisher
warning. Code-sign the finished release build before public distribution.
