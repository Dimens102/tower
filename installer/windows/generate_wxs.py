#!/usr/bin/env python3
"""Generate the WiX source for the Tower Control MSI."""

from __future__ import annotations

import hashlib
import uuid
from pathlib import Path
from xml.sax.saxutils import escape


ROOT = Path(__file__).resolve().parents[2]
WINDOWS = ROOT / "windows"
OUTPUT = Path(__file__).resolve().parent / "generated" / "Tower-Control.wxs"
WIX_NS = "http://schemas.microsoft.com/wix/2006/wi"
VERSION_DISPLAY = "0.11.05"
VERSION_MSI = "0.11.5"
UPGRADE_CODE = "6B9BA4B0-6F56-45E6-94BC-AEF7A7C6C94B"
PRODUCT_CODE = "B3E29CAE-8F02-49ED-8C83-AC03DA7926E1"


def wix_id(prefix: str, value: str) -> str:
    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()[:20]
    return f"{prefix}_{digest}"


def component_guid(value: str) -> str:
    namespace = uuid.UUID("fbbfa216-5408-4adf-a951-1ed63f6a59cb")
    return str(uuid.uuid5(namespace, value)).upper()


def emit_directory(lines: list[str], folder: Path, indent: str) -> list[str]:
    component_ids: list[str] = []
    relative_folder = folder.relative_to(WINDOWS)
    directory_id = "INSTALLFOLDER" if folder == WINDOWS else wix_id(
        "Dir", relative_folder.as_posix()
    )

    if folder != WINDOWS:
        lines.append(
            f'{indent}<Directory Id="{directory_id}" Name="{escape(folder.name)}">'
        )
        indent += "  "

    for file_path in sorted(p for p in folder.iterdir() if p.is_file()):
        relative = file_path.relative_to(WINDOWS).as_posix()
        component_id = wix_id("Cmp", relative)
        file_id = wix_id("File", relative)
        component_ids.append(component_id)
        source = f"$(var.WindowsSource)/{relative}"
        lines.append(
            f'{indent}<Component Id="{component_id}" '
            f'Guid="{component_guid(relative)}" Win64="yes">'
        )
        lines.append(
            f'{indent}  <File Id="{file_id}" Name="{escape(file_path.name)}" '
            f'Source="{escape(source)}" KeyPath="yes" />'
        )
        lines.append(f"{indent}</Component>")

    for child in sorted(p for p in folder.iterdir() if p.is_dir()):
        component_ids.extend(emit_directory(lines, child, indent))

    if folder != WINDOWS:
        indent = indent[:-2]
        lines.append(f"{indent}</Directory>")

    return component_ids


def main() -> None:
    if not WINDOWS.is_dir():
        raise SystemExit(f"Windows source directory not found: {WINDOWS}")

    directory_lines: list[str] = []
    component_ids = emit_directory(directory_lines, WINDOWS, "        ")
    launcher_file_id = wix_id("File", "Start-Tower-Control.vbs")
    icon_file_id = wix_id("File", "assets/tower-icon-tray.ico")

    content: list[str] = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<Wix xmlns="{WIX_NS}">',
        f'  <Product Id="{PRODUCT_CODE}" Name="Tower Control" '
        f'Language="1033" Version="{VERSION_MSI}" Manufacturer="RF Tower Project" '
        f'UpgradeCode="{UPGRADE_CODE}">',
        '    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" '
        'Description="RF Tower Windows control application and background agent" />',
        '    <MediaTemplate EmbedCab="yes" />',
        '    <MajorUpgrade DowngradeErrorMessage="A newer version of Tower Control is already installed." />',
        f'    <Property Id="ARPCOMMENTS" Value="Tower Control {VERSION_DISPLAY}" />',
        '    <Property Id="ARPNOREPAIR" Value="1" />',
        '    <Property Id="ARPHELPLINK" Value="https://github.com/Dimens102/tower" />',
        '    <Icon Id="TowerIcon.ico" SourceFile="$(var.WindowsSource)/assets/tower-icon-tray.ico" />',
        '    <Property Id="ARPPRODUCTICON" Value="TowerIcon.ico" />',
        '    <Directory Id="TARGETDIR" Name="SourceDir">',
        '      <Directory Id="ProgramFiles64Folder">',
        '        <Directory Id="INSTALLFOLDER" Name="Tower Control">',
    ]
    content.extend(directory_lines)
    content.extend([
        '        </Directory>',
        '      </Directory>',
        '      <Directory Id="ProgramMenuFolder">',
        '        <Directory Id="ProgramMenuTowerFolder" Name="Tower Control" />',
        '      </Directory>',
        '      <Directory Id="DesktopFolder" />',
        '    </Directory>',
        '    <DirectoryRef Id="ProgramMenuTowerFolder">',
        f'      <Component Id="Cmp_StartMenuShortcut" Guid="{component_guid("shortcut/start-menu")}" Win64="yes">',
        f'        <Shortcut Id="StartMenuShortcut" Name="Tower Control" Target="[SystemFolder]wscript.exe" '
        f'Arguments="&quot;[#%s]&quot;" WorkingDirectory="INSTALLFOLDER" Icon="TowerIcon.ico" />' % launcher_file_id,
        '        <RemoveFolder Id="RemoveProgramMenuTowerFolder" On="uninstall" />',
        '        <RegistryValue Root="HKLM" Key="Software\\RF Tower Project\\Tower Control" '
        'Name="StartMenuShortcut" Type="integer" Value="1" KeyPath="yes" />',
        '      </Component>',
        '    </DirectoryRef>',
        '    <DirectoryRef Id="DesktopFolder">',
        f'      <Component Id="Cmp_DesktopShortcut" Guid="{component_guid("shortcut/desktop")}" Win64="yes">',
        f'        <Shortcut Id="DesktopShortcut" Name="Tower Control" Target="[SystemFolder]wscript.exe" '
        f'Arguments="&quot;[#%s]&quot;" WorkingDirectory="INSTALLFOLDER" Icon="TowerIcon.ico" />' % launcher_file_id,
        '        <RegistryValue Root="HKLM" Key="Software\\RF Tower Project\\Tower Control" '
        'Name="DesktopShortcut" Type="integer" Value="1" KeyPath="yes" />',
        '      </Component>',
        '    </DirectoryRef>',
        '    <CustomAction Id="SetPowerShellPath" Property="POWERSHELLEXE" '
        'Value="[SystemFolder]WindowsPowerShell\\v1.0\\powershell.exe" />',
        '    <CustomAction Id="ConfigureTower" Property="POWERSHELLEXE" Execute="deferred" '
        'Impersonate="no" Return="ignore" ExeCommand="-NoProfile -ExecutionPolicy Bypass '
        '-File &quot;[INSTALLFOLDER]Msi-Configure-Tower.ps1&quot; -Mode Install" />',
        '    <CustomAction Id="RemoveTowerIntegration" Property="POWERSHELLEXE" Execute="deferred" '
        'Impersonate="no" Return="ignore" ExeCommand="-NoProfile -ExecutionPolicy Bypass '
        '-File &quot;[INSTALLFOLDER]Msi-Configure-Tower.ps1&quot; -Mode Remove" />',
        '    <InstallExecuteSequence>',
        '      <Custom Action="SetPowerShellPath" After="CostFinalize">1</Custom>',
        '      <Custom Action="ConfigureTower" After="InstallFiles">NOT Installed</Custom>',
        '      <Custom Action="RemoveTowerIntegration" After="RemoveShortcuts">REMOVE~=&quot;ALL&quot; AND NOT UPGRADINGPRODUCTCODE</Custom>',
        '    </InstallExecuteSequence>',
        '    <Feature Id="Complete" Title="Tower Control" Level="1" Absent="disallow">',
    ])
    for component_id in component_ids:
        content.append(f'      <ComponentRef Id="{component_id}" />')
    content.extend([
        '      <ComponentRef Id="Cmp_StartMenuShortcut" />',
        '      <ComponentRef Id="Cmp_DesktopShortcut" />',
        '    </Feature>',
        '  </Product>',
        '</Wix>',
        '',
    ])

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(content), encoding="utf-8")
    print(OUTPUT)


if __name__ == "__main__":
    main()
