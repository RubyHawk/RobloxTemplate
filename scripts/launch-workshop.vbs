Option Explicit

Dim fileSystem, shell, scriptsFolder, launcherPath, command
Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptsFolder = fileSystem.GetParentFolderName(WScript.ScriptFullName)
launcherPath = fileSystem.BuildPath(scriptsFolder, "launcher.ps1")
command = "powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & launcherPath & """"

' Window style 0 keeps the PowerShell host invisible. The WPF launcher creates its
' own visible window and immediately returns control to START_HERE.cmd.
shell.Run command, 0, False
