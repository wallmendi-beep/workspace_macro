#Requires AutoHotkey v2.0
#SingleInstance Off
DetectHiddenWindows true

Persistent(true)
g := Gui("+AlwaysOnTop", "RegiMacro Sandbox Large")
g.Show("w640 h400")
WinActivate("ahk_id " g.Hwnd)
Sleep 50
FileAppend "DECOY_HWND=" g.Hwnd "`n", "*"

SetTimer () => 0, 1000
