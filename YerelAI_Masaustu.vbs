Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "C:\Users\Salih\Desktop\yerelai\desktop"
WshShell.Run """C:\Users\Salih\Desktop\yerelai\desktop\node_modules\electron\dist\electron.exe"" .", 1, False
