' conhost --headless : jamais de fenetre, meme si Windows Terminal est le terminal par defaut
Set sh = CreateObject("WScript.Shell")
extra = ""
For i = 1 To WScript.Arguments.Count - 1
  extra = extra & " " & WScript.Arguments(i)
Next
sh.Run "conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & WScript.Arguments(0) & """" & extra, 0, False