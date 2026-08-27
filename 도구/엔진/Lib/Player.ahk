; ============================================================
; RegiMacro — 재생 엔진 (Lib\Player.ahk)
; 상태머신: 정지 → 실행중 ⇄ 일시정지
; 스키마 v2.0 완벽 호환, 단일 모니터 정규화 좌표 리매핑,
; 대상 창 사전 확정(Confirm Modal), 포커스 이탈 차단(Focus Guard),
; 비최대화 창 DWM 최대화(X/Y/W/H 전수검증 및 실패시 원복),
; 모니터 물리 Origin(ml/mt) 적용 및 Fail-Closed 안전 보호.
; ============================================================
#Requires AutoHotkey v2.0

class Player {
    static STOPPED := "정지"
    static RUNNING := "실행중"
    static PAUSED  := "일시정지"

    __New(macro, cfg) {
        this.macro := macro
        this.cfg := cfg
        this.dryRun := cfg.dryRun
        this.pasteMode := cfg.pasteMode
        this.defInterval := cfg.defaultIntervalMs
        this.state := Player.STOPPED

        ; 스키마 버전 확인
        this.version := macro.Has("version") ? Integer(macro["version"]) : 1

        ; 단계(스텝) 평탄화: {s: 구간번호, c: 클립번호} 목록
        this.steps := []
        this.sectionStarts := Map()
        for sIdx, sec in macro["sections"] {
            clips := sec["clips"]
            this.sectionStarts[sIdx] := this.steps.Length + 1
            for cIdx, clip in clips
                this.steps.Push({s: sIdx, c: cIdx})
        }
        this.stepIdx := 0      ; 1 기반, 0 = 시작 전
        this.nextAt := 0       ; 다음 클립 실행 예정 시각(A_TickCount)
        this.pausedAt := 0
        this.logs := []
        this.onStop := ""      ; 콜백: onStop(reason)

        ; 대상 창 및 모니터 실행 컨텍스트
        this.targetHwnd := 0
        this.targetMon := 1
        this.monOriginX := 0   ; 모니터 물리 origin X (ml)
        this.monOriginY := 0   ; 모니터 물리 origin Y (mt)
        this.monWidth := 1920
        this.monHeight := 1080
        this.monLeft := 0
        this.monTop := 0
        this.monRight := 1920
        this.monBottom := 1080
        this.workLeft := 0     ; 작업영역 (wl)
        this.workTop := 0      ; 작업영역 (wt)
        this.workRight := 1920 ; 작업영역 (wr)
        this.workBottom := 1080  ; 작업영역 (wb)
        this.origWinPos := ""  ; 복원용 {x, y, w, h, minmax}
    }

    ; ---------- 정보 조회 ----------
    TotalSteps() => this.steps.Length
    CurrentStep() => this.stepIdx
    SectionCount() => this.macro["sections"].Length

    Label(secIdx) {
        sec := this.macro["sections"][secIdx]
        return sec.Has("label") ? String(sec["label"]) : ("구간 " secIdx)
    }

    ClipSummary(step) {
        clip := this.GetClip(step)
        t := String(clip["type"])
        if (t = "mouse") {
            cMode := clip.Has("coordMode") ? String(clip["coordMode"]) : "screen"
            return "클릭 (" clip["x"] ", " clip["y"] ") [" cMode "]"
        }
        if (t = "key")
            return "키: " clip["key"]
        v := clip.Has("value") ? String(clip["value"]) : ""
        v := Trim(StrReplace(v, "`n", " "))
        if (StrLen(v) > 24)
            v := SubStr(v, 1, 24) "…"
        return "입력: " v
    }

    GetClip(step) {
        return this.macro["sections"][step.s]["clips"][step.c]
    }

    JumpToSection(sIdx) {
        if (!this.sectionStarts.Has(sIdx))
            return
        this.stepIdx := this.sectionStarts[sIdx]
        if (this.state = Player.RUNNING)
            this.nextAt := A_TickCount
        this.Log("구간 이동 → " this.Label(sIdx))
    }

    IntervalOf(step) {
        clip := this.macro["sections"][step.s]["clips"][step.c]
        iv := ""
        if (clip.Has("interval"))
            iv := String(clip["interval"])
        if (iv = "" || !IsNumber(iv))
            return this.defInterval
        return Integer(iv)
    }

    Log(msg) {
        this.logs.Push(A_Hour ":" A_Min ":" A_Sec " " msg)
        if (this.logs.Length > 200)
            this.logs.RemoveAt(1)
    }

    ; ---------- 대상 창 및 모니터 사전 검증 & 확정 (Fail-Closed) ----------
    PrepareTarget() {
        cfg := this.cfg
        isQuiet := (cfg.HasOwnProp("quiet") && cfg.quiet)

        ; 1. v1 실제입력 차단
        if (this.version < 2 && !this.dryRun) {
            if (!isQuiet)
                MsgBox("v1 스키마 매크로는 실제 입력을 실행할 수 없습니다.`n(좌표계 안전을 위해 v2로 마이그레이션된 매크로만 실제입력 가능)", "RegiMacro 실행 차단", "Iconx")
            this.Log("[오류] v1 스키마 실제입력 차단 (v2 마이그레이션 필요)")
            return false
        }

        ; 2. ScaleMode 검증 (v2 유산 screen 매크로는 off만 허용)
        if (!this.dryRun && cfg.scaleMode != "off") {
            if (!isQuiet)
                MsgBox("v2 유산 매크로는 ScaleMode=off (원본 정규화 origin 매핑)만 지원합니다.`nconfig.ini의 ScaleMode를 off로 변경하세요.", "RegiMacro 설정 오류", "Iconx")
            this.Log("[오류] ScaleMode=" cfg.scaleMode " 실행 차단 (off만 허용)")
            return false
        }

        ; 3. 대상 창 감지 (Foreground 활성창)
        hwnd := WinActive("A")
        if (!hwnd && cfg.targetTitle != "" && WinExist(cfg.targetTitle)) {
            hwnd := WinExist(cfg.targetTitle)
        }
        if (!hwnd) {
            if (!this.dryRun) {
                if (!isQuiet)
                    MsgBox("활성화된 대상 창을 찾을 수 없습니다.`n업무 프로그램 창을 먼저 활성화한 후 실행하세요.", "RegiMacro 대상 창 오류", "Iconx")
                this.Log("[오류] 활성화된 Foreground 창 없음")
                return false
            }
            hwnd := 0
        }
        winTitle := hwnd ? WinGetTitle(hwnd) : "모의 실행 창"
        winClass := hwnd ? WinGetClass(hwnd) : "MockClass"
        winProcess := hwnd ? WinGetProcessName(hwnd) : "MockApp.exe"

        ; config.ini 대상 창 필터 검증 (실제 입력 시 검증)
        if (!this.dryRun) {
            if (cfg.targetTitle != "" && !InStr(winTitle, cfg.targetTitle)) {
                MsgBox("활성화된 창이 대상 창 제목과 일치하지 않습니다.`n현재 창: " winTitle "`n필요 조건: " cfg.targetTitle, "RegiMacro 대상 창 불일치", "Iconx")
                this.Log("[오류] 대상 창 제목 불일치: " winTitle)
                return false
            }
            if (cfg.targetClass != "" && winClass != cfg.targetClass) {
                MsgBox("활성화된 창 클래스가 일치하지 않습니다.`n현재: " winClass "`n필요: " cfg.targetClass, "RegiMacro 대상 창 불일치", "Iconx")
                this.Log("[오류] 대상 창 클래스 불일치: " winClass)
                return false
            }
            if (cfg.targetExe != "" && winProcess != cfg.targetExe) {
                MsgBox("활성화된 실행파일이 일치하지 않습니다.`n현재: " winProcess "`n필요: " cfg.targetExe, "RegiMacro 대상 창 불일치", "Iconx")
                this.Log("[오류] 대상 실행파일 불일치: " winProcess)
                return false
            }
        }

        ; 4. 대상 창 위치 및 모니터 판정
        targetMon := 1
        if (hwnd) {
            WinGetPos(&wx, &wy, &ww, &wh, hwnd)
            centerX := wx + ww // 2
            centerY := wy + wh // 2
            monCount := MonitorGetCount()
            loop monCount {
                MonitorGet(A_Index, &ml, &mt, &mr, &mb)
                if (centerX >= ml && centerX < mr && centerY >= mt && centerY < mb) {
                    targetMon := A_Index
                    break
                }
            }
        }
        this.targetMon := targetMon
        MonitorGet(targetMon, &ml, &mt, &mr, &mb)
        MonitorGetWorkArea(targetMon, &wl, &wt, &wr, &wb)
        
        ; 물리 모니터 Origin (ml, mt) 확정 (계약 준수)
        this.monLeft := ml
        this.monTop := mt
        this.monRight := mr
        this.monBottom := mb
        this.monOriginX := ml
        this.monOriginY := mt
        this.monWidth := mr - ml
        this.monHeight := mb - mt
        
        ; 작업영역 (최대화/HUD용)
        this.workLeft := wl
        this.workTop := wt
        this.workRight := wr
        this.workBottom := wb

        ; 5. 실제 입력 모드 시: 사용자 사전 확정 모달 (무검증 자동실행 방지)
        if (!this.dryRun) {
            confirmMsg := "아래 대상 창에 실제 입력을 실행하시겠습니까?`n`n"
                        . "• 창 제목: " winTitle "`n"
                        . "• 프로세스: " winProcess "`n"
                        . "• 클래스: " winClass "`n"
                        . "• 실행 모니터: " targetMon "번 (좌표: " ml ", " mt " ~ " mr ", " mb ")`n`n"
                        . "※ 확인을 누르면 매크로가 시작됩니다."
            
            res := MsgBox(confirmMsg, "RegiMacro 대상 창 확정", "YesNo Iconi Default1")
            if (res != "Yes") {
                this.Log("[취소] 사용자가 대상 창 실행을 취소했습니다.")
                return false
            }
        }

        this.targetHwnd := hwnd

        ; 6. 좌표계 분석 (혼합 모드 차단 & client 메타데이터 필수 검증)
        hasScreenClip := false
        hasClientClip := false
        for _, step in this.steps {
            c := this.GetClip(step)
            if (String(c["type"]) = "mouse") {
                cm := c.Has("coordMode") ? String(c["coordMode"]) : "screen"
                if (cm = "client")
                    hasClientClip := true
                else
                    hasScreenClip := true
            }
        }

        ; 단일 파일 내 screen과 client 혼합 모드 절대 금지 (Fail-Closed)
        if (hasScreenClip && hasClientClip) {
            if (!this.dryRun && !isQuiet)
                MsgBox("한 매크로 파일 내에 screen과 client 좌표계가 혼합되어 있어 실행할 수 없습니다.", "RegiMacro 혼합 모드 차단", "Iconx")
            this.Log("[오류] screen/client 혼합 매크로 실행 차단")
            return false
        }

        ; client 모드 메타데이터 필수 검증 (누락, 비정수(String/Float 배제), 0 이하, 크기 불일치 전수 차단)
        if (hasClientClip) {
            if (!this.macro.Has("clientResolution")) {
                if (!this.dryRun && !isQuiet)
                    MsgBox("client 좌표계 매크로는 clientResolution 메타데이터가 필수입니다.", "RegiMacro 메타데이터 누락 차단", "Iconx")
                this.Log("[오류] clientResolution 메타데이터 누락 차단")
                return false
            }
            cRes := this.macro["clientResolution"]
            if (!cRes.Has("width") || !cRes.Has("height")) {
                if (!this.dryRun && !isQuiet)
                    MsgBox("clientResolution에 width/height 필드가 누락되었습니다.", "RegiMacro 필드 누락 차단", "Iconx")
                this.Log("[오류] clientResolution 필드 누락 차단")
                return false
            }
            wVal := cRes["width"]
            hVal := cRes["height"]
            if (Type(wVal) != "Integer" || Type(hVal) != "Integer" || wVal <= 0 || hVal <= 0) {
                if (!this.dryRun && !isQuiet)
                    MsgBox("clientResolution 형식 오류 (width/height가 양의 정수 Integer 타입이 아님).", "RegiMacro 형식 오류 차단", "Iconx")
                this.Log("[오류] clientResolution 형식 오류로 차단")
                return false
            }

            if (!this.dryRun) {
                WinGetClientPos(&cx, &cy, &cw, &ch, hwnd)
                reqW := Integer(wVal)
                reqH := Integer(hVal)
                if (Abs(cw - reqW) > 10 || Abs(ch - reqH) > 10) {
                    if (!isQuiet)
                        MsgBox("Client 창 크기가 녹화 당시와 일치하지 않습니다.`n녹화: " reqW "x" reqH "`n현재: " cw "x" ch, "RegiMacro Client 크기 불일치", "Iconx")
                    this.Log("[오류] Client 크기 불일치로 차단")
                    return false
                }
            }
        }

        if (hasScreenClip && !this.dryRun) {
            minMax := WinGetMinMax(hwnd)
            if (minMax == 0) {
                ; 비최대화 상태 -> 원본 위치 저장 후 최대화 시도
                this.origWinPos := {x: wx, y: wy, w: ww, h: wh, minMax: minMax}
                WinMaximize(hwnd)
                
                ; 최대화 완료 대기
                maxOk := false
                loop 20 {
                    Sleep 50
                    if (WinGetMinMax(hwnd) == 1) {
                        maxOk := true
                        break
                    }
                }
                
                if (!maxOk) {
                    ; 최대화 실패 시 즉시 원복 후 차단
                    try WinRestore(hwnd)
                    MsgBox("창 최대화에 실패했습니다. 안전을 위해 실행을 중단합니다.", "RegiMacro 안전 차단", "Iconx")
                    this.Log("[오류] WinMaximize 실패")
                    return false
                }
            }

            ; 최대화 상태에서 DWM 허용오차 (+-25px) X/Y/W/H 전수검증
            WinGetPos(&nwx, &nwy, &nww, &nwh, hwnd)
            tol := 25
            ; 최대화된 창은 물리 모니터(ml, mt) 또는 작업영역(wl, wt) 부근에 도킹됨
            xOk := (Abs(nwx - ml) <= tol || Abs(nwx - wl) <= tol)
            yOk := (Abs(nwy - mt) <= tol || Abs(nwy - wt) <= tol)
            wOk := (Abs(nww - this.monWidth) <= tol || Abs(nww - (wr - wl)) <= tol)
            hOk := (Abs(nwh - this.monHeight) <= tol || Abs(nwh - (wb - wt)) <= tol)

            if (!xOk || !yOk || !wOk || !hOk) {
                ; 위치/크기 불일치 시 복원 후 차단
                if (this.origWinPos != "") {
                    try {
                        WinRestore(hwnd)
                        WinMove(this.origWinPos.x, this.origWinPos.y, this.origWinPos.w, this.origWinPos.h, hwnd)
                    }
                }
                MsgBox("최대화된 창의 영역이 대상 모니터와 일치하지 않습니다.`n(X:" nwx ", Y:" nwy ", W:" nww ", H:" nwh ")`n안전을 위해 실행을 중단합니다.", "RegiMacro 영역 불일치 차단", "Iconx")
                this.Log("[오류] 최대화 DWM 허용오차 초과 (X/Y/W/H 불일치)")
                return false
            }
            this.Log("대상 창 최대화 검증 통과 (모니터 " targetMon "번)")
        }

        this.Log("[사전검증 완료] 대상: " winTitle " (모니터 " targetMon "번, Origin: " ml ", " mt ")")
        return true
    }

    ; ---------- 제어 ----------
    StartOrResume() {
        if (this.state = Player.RUNNING) {
            this.Pause()   ; 실행 중에 트리거를 누르면 일시정지 토글
            return
        }
        if (this.state = Player.PAUSED) {
            this.nextAt += A_TickCount - this.pausedAt   ; 멈춘 만큼 일정 이동
            this.state := Player.RUNNING
            this.Log("재개")
            return
        }
        if (this.steps.Length = 0)
            return

        ; 실제 입력 시작 전 사전 검증
        if (!this.PrepareTarget())
            return

        if (this.stepIdx < 1 || this.stepIdx > this.steps.Length)
            this.stepIdx := 1
        this.state := Player.RUNNING
        this.nextAt := A_TickCount   ; 첫 클립 즉시 실행
        this.Log((this.dryRun ? "[모의모드] " : "[실제입력] ") "재생 시작")
    }

    Pause() {
        if (this.state = Player.RUNNING) {
            this.pausedAt := A_TickCount
            this.state := Player.PAUSED
            this.Log("일시정지")
        }
    }

    Stop(reason := "종료") {
        wasRunning := (this.state != Player.STOPPED)
        this.state := Player.STOPPED
        if (wasRunning) {
            this.Log("정지 — " reason)
            
            ; 창 원래 위치 복원 (옵션 설정 시)
            if (this.cfg.restoreOnStop && this.origWinPos != "" && this.targetHwnd && WinExist(this.targetHwnd)) {
                try {
                    WinRestore(this.targetHwnd)
                    WinMove(this.origWinPos.x, this.origWinPos.y, this.origWinPos.w, this.origWinPos.h, this.targetHwnd)
                    this.Log("대상 창 원래 크기 복원 완료")
                }
                this.origWinPos := ""
            }

            if (this.onStop != "") {
                try {
                    if (HasMethod(this.onStop))
                        (this.onStop)(reason)
                    else if (this.onStop is Func)
                        this.onStop.Call(reason)
                }
            }
        }
    }

    GoHome() {
        if (this.steps.Length = 0)
            return
        this.stepIdx := 1
        if (this.state = Player.RUNNING)
            this.nextAt := A_TickCount
        this.Log("처음 구간으로 이동")
    }

    GoEndStop() {
        this.Stop("End 키")
    }

    NextSection() {
        if (this.steps.Length = 0)
            return
        target := 0
        for sIdx, stIdx in this.sectionStarts
            if (stIdx > this.stepIdx && (target = 0 || stIdx < target))
                target := stIdx
        if (target = 0)
            target := this.steps.Length   ; 마지막 구간이면 마지막 클립으로
        this.stepIdx := target
        if (this.state = Player.RUNNING)
            this.nextAt := A_TickCount
        this.Log("건너뛰기 → " this.Label(this.steps[target].s))
    }

    PrevSection() {
        if (this.steps.Length = 0)
            return
        curStart := 1
        if (this.stepIdx >= 1 && this.stepIdx <= this.steps.Length)
            curStart := this.sectionStarts[this.steps[this.stepIdx].s]
        target := 0
        for sIdx, stIdx in this.sectionStarts
            if (stIdx < curStart && stIdx > target)
                target := stIdx
        if (target = 0)
            target := 1
        this.stepIdx := target
        if (this.state = Player.RUNNING)
            this.nextAt := A_TickCount
        this.Log("이전 구간으로 ← " this.Label(this.steps[target].s))
    }

    ; ---------- 타이머 구동부 ----------
    Tick() {
        if (this.state != Player.RUNNING)
            return
        if (A_TickCount < this.nextAt)
            return
        step := this.steps[this.stepIdx]
        
        ok := this.Execute(step)
        if (!ok) {
            ; Execute 실패 시 fail-closed 정지
            return
        }

        if (this.stepIdx >= this.steps.Length) {
            this.Stop("재생 완료")
            return
        }
        this.stepIdx++
        this.nextAt := A_TickCount + this.IntervalOf(this.steps[this.stepIdx])
    }

    Execute(step) {
        ; 1. 실제 입력 모드 시: 포커스 이탈 가드 (Focus Loss Guard)
        if (!this.dryRun) {
            if (!this.targetHwnd || !WinExist(this.targetHwnd)) {
                this.Stop("대상 창 소멸 — 입력 중단")
                MsgBox("대상 창이 닫혔거나 존재하지 않아 실행을 즉시 정지합니다.", "RegiMacro 안전 정지", "Iconx")
                return false
            }
            if (WinActive("A") != this.targetHwnd) {
                this.Stop("포커스 이탈 — 다른 창 활성화로 입력 차단")
                MsgBox("대상 창이 비활성화(포커스 이탈)되어 안전을 위해 입력을 즉시 정지합니다.", "RegiMacro 포커스 이탈 차단", "Iconx")
                return false
            }
        }

        clip := this.macro["sections"][step.s]["clips"][step.c]
        t := String(clip["type"])

        if (t = "mouse") {
            cMode := clip.Has("coordMode") ? String(clip["coordMode"]) : "screen"
            rawX := Integer(clip["x"])
            rawY := Integer(clip["y"])

            finalX := rawX
            finalY := rawY

            if (cMode = "client") {
                CoordMode "Mouse", "Client"
                finalX := rawX
                finalY := rawY
            } else {
                ; Screen 좌표 (v2 정규화 좌표 -> 대상 모니터 물리 Origin 매핑)
                CoordMode "Mouse", "Screen"
                finalX := this.monOriginX + rawX
                finalY := this.monOriginY + rawY

                ; Fail-Closed 좌표 범위 검증 (물리 모니터 경계 [monLeft ~ monRight, monTop ~ monBottom])
                if (finalX < this.monLeft || finalX >= this.monRight || finalY < this.monTop || finalY >= this.monBottom) {
                    this.Stop("좌표 이탈 (" finalX ", " finalY ") — 대상 모니터 범위를 벗어나 클릭 차단")
                    if (!this.dryRun)
                        MsgBox("마우스 클릭 좌표가 대상 모니터 범위를 벗어났습니다.`n계산된 좌표: (" finalX ", " finalY ")`n모니터 영역: [" this.monLeft ", " this.monTop " ~ " this.monRight ", " this.monBottom "]", "RegiMacro 좌표 오류", "Iconx")
                    return false
                }
            }

            ; 모의 모드 처리
            if (this.dryRun) {
                this.Log("[모의] 클릭 (" rawX ", " rawY ") -> " cMode "(" finalX ", " finalY ") [모니터 " this.targetMon "]")
                return true
            }

            ; 실제 입력
            MouseMove finalX, finalY, 0
            Click finalX, finalY
            this.Log("클릭 -> " cMode "(" finalX ", " finalY ")")

        } else if (t = "key") {
            k := String(clip["key"])
            if (this.dryRun) {
                this.Log("[모의] 키: " k)
                return true
            }
            if (k = "ENTER")
                Send "{Enter}"
            else if (k = "TAB")
                Send "{Tab}"
            this.Log("키: " k)

        } else if (t = "text") {
            v := clip.Has("value") ? String(clip["value"]) : ""
            method := clip.Has("input_method") ? String(clip["input_method"]) : "typing"
            
            if (this.dryRun) {
                this.Log("[모의] " this.ClipSummary(step))
                return true
            }

            if (v != "") {
                if (this.pasteMode && InStr(method, "typing") != 1) {
                    A_Clipboard := v
                    ClipWait(1)
                    Send "^v"
                } else {
                    SendText v
                }
            }
            this.Log(this.ClipSummary(step))
        }

        return true
    }
}
