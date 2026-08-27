; ============================================================
; RegiMacro — 메인 진입점 (RegiMacro.ahk)
; 실행: AutoHotkey v2 필요. 이 파일을 실행하면 매크로 JSON을
;       선택하고, 인디케이터가 뜬 후 핫키로 재생을 제어한다.
; 안전: 기본값은 모의 모드(DryRun) — 실제 입력 없이 로그만 남긴다.
;       실제 입력 모드는 config.ini에서 DryRun=0 으로 변경.
; ============================================================
#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode "Mouse", "Screen"
SetKeyDelay -1, -1
SendMode "Input"

#Include Lib\Json.ahk
#Include Lib\Player.ahk
#Include Lib\Studio.ahk
#Include Lib\Indicator.ahk

; ---------- DPI 인식 모드 (Per-Monitor v2) ----------
try DllCall("SetThreadDpiAwarenessContext", "ptr", -4)

; ---------- 설정 로드 (config.ini — 사용자 커스텀 지점) ----------
cfgFile := A_ScriptDir "\config.ini"
cfg := {
    dryRun:            IniRead(cfgFile, "Playback", "DryRun", "1") = "1",
    pasteMode:         IniRead(cfgFile, "Playback", "PasteMethod", "1") = "1",
    defaultIntervalMs: Integer(IniRead(cfgFile, "Playback", "DefaultIntervalMs", "2000")),
    restoreOnStop:     IniRead(cfgFile, "Playback", "RestoreWindowOnStop", "1") = "1",
    targetTitle:       IniRead(cfgFile, "Target", "WinTitle", ""),
    targetClass:       IniRead(cfgFile, "Target", "WinClass", ""),
    targetExe:         IniRead(cfgFile, "Target", "WinExe", ""),
    scaleMode:         IniRead(cfgFile, "Display", "ScaleMode", "off"),
    baseWidth:         Integer(IniRead(cfgFile, "Display", "BaseWidth", "1920")),
    baseHeight:        Integer(IniRead(cfgFile, "Display", "BaseHeight", "1080")),
    hkTrigger: IniRead(cfgFile, "Hotkeys", "Trigger", "^!r"),
    hkPause:   IniRead(cfgFile, "Hotkeys", "PauseKey", "Pause"),
    hkResume:  IniRead(cfgFile, "Hotkeys", "ResumeKey", "ScrollLock"),
    hkHome:    IniRead(cfgFile, "Hotkeys", "HomeKey", "Home"),
    hkEnd:     IniRead(cfgFile, "Hotkeys", "EndKey", "End"),
    hkNext:    IniRead(cfgFile, "Hotkeys", "NextSectionKey", "PgUp"),
    hkPrev:    IniRead(cfgFile, "Hotkeys", "PrevSectionKey", "PgDn")
}

; ---------- 매크로 파일 선택 ----------
jsonPath := ""
if (A_Args.Length >= 1)
    jsonPath := A_Args[1]
else {
    startDir := A_ScriptDir "\..\..\변환 결과"
    jsonPath := FileSelect(1, startDir, "재생할 매크로 JSON 선택", "매크로 초안(*_초안.json)")
}
if (!jsonPath || !FileExist(jsonPath))
    ExitApp

macro := JsonParser.Load(FileRead(jsonPath, "UTF-8"))
macroPlayer := Player(macro, cfg)

; 재생 완료 콜백
macroPlayer.onStop := OnPlaybackStop

; UI 구동: 스튜디오 에디터 + 최상위 플로팅 HUD
studioUI := Studio(macroPlayer, String(macro["name"]) " — RegiMacro Studio" (cfg.dryRun ? " [모의 모드]" : " [실제 입력 모드]"))
hudOverlay := OverlayIndicator(macroPlayer, String(macro["name"]) (cfg.dryRun ? " (모의)" : ""))

OnPlaybackStop(reason) {
    if (InStr(reason, "완료"))
        TrayTip("RegiMacro", "매크로 재생이 완료되었습니다.")
}

; ---------- 핫키 등록 (config.ini로 커스텀 가능 / Esc는 의도적으로 미할당) ----------
BindHK(name, fn, desc) {
    try
        Hotkey(name, fn)
    catch
        MsgBox("핫키 등록 실패: " name "`n(" desc ")`nconfig.ini의 다른 키와 겹치는지 확인하세요.", "RegiMacro 경고")
}

BindHK(cfg.hkTrigger, (*) => macroPlayer.StartOrResume(), "실행/일시정지 토글")
BindHK(cfg.hkPause,   (*) => macroPlayer.Pause(),           "일시정지")
BindHK(cfg.hkResume,  (*) => macroPlayer.StartOrResume(),   "재개")
BindHK(cfg.hkHome,    (*) => macroPlayer.GoHome(),          "처음으로")
BindHK(cfg.hkEnd,     (*) => macroPlayer.GoEndStop(),       "종료")
BindHK(cfg.hkNext,    (*) => macroPlayer.NextSection(),     "다음 구간 건너뛰기")
BindHK(cfg.hkPrev,    (*) => macroPlayer.PrevSection(),     "이전 구간")

; 인디케이터/HUD 표시/숨김 토글 (Ctrl+Alt+I 기본 — 시스템 충돌 없는 보조키)
try Hotkey("^!i", (*) => hudOverlay.ToggleVisible())

; ---------- 타이머 구동 ----------
TickAll() {
    macroPlayer.Tick()
    studioUI.Update()
    hudOverlay.Update()
}
SetTimer TickAll, 50

TrayTip("RegiMacro", (cfg.dryRun ? "모의 모드로 대기 중입니다." : "실제 입력 모드입니다. 주의하세요.") "`n트리거: " cfg.hkTrigger)

