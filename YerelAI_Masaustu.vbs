Set FSO = CreateObject("Scripting.FileSystemObject")
Set WshShell = CreateObject("WScript.Shell")
RootDir = FSO.GetParentFolderName(WScript.ScriptFullName)
DesktopDir = FSO.BuildPath(RootDir, "desktop")
ElectronExe = FSO.BuildPath(DesktopDir, "node_modules\electron\dist\electron.exe")

If FSO.FileExists(ElectronExe) Then
    WshShell.CurrentDirectory = DesktopDir
    WshShell.Run """" & ElectronExe & """ .", 1, False
Else
    KurulumPs1 = FSO.BuildPath(RootDir, "kurulum.ps1")
    WshShell.CurrentDirectory = RootDir
    WshShell.Run "powershell -NoProfile -ExecutionPolicy Bypass -File """ & KurulumPs1 & """", 1, False
End If
