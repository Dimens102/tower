Option Explicit

Dim shell, fileSystem, scriptPath, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptPath = fileSystem.BuildPath( _
    fileSystem.GetParentFolderName(WScript.ScriptFullName), _
    "Tower-Control.ps1")

command = "powershell.exe -NoProfile -WindowStyle Hidden " & _
    "-ExecutionPolicy Bypass -File """ & scriptPath & """"

shell.Run command, 0, False
