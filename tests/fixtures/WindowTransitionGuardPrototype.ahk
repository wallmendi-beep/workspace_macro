#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows true
SetTitleMatchMode 2

/**
 * RM-WINDOW-004: expectedWindow allowlist 전환 가드 프로토타입 (보완 오라클 14개 규격 준수)
 */
class WindowTransitionGuardPrototype {
    static PROFILES := Map(
        "main", { title: "RegiMacro Sandbox Main", winClass: "AutoHotkeyGUI", width: 800, height: 600, checkpoint: false },
        "largePopup", { title: "RegiMacro Sandbox Large", winClass: "AutoHotkeyGUI", width: 640, height: 400, checkpoint: false },
        "smallPopup", { title: "RegiMacro Sandbox Small", winClass: "AutoHotkeyGUI", width: 420, height: 180, checkpoint: true }
    )

    static ALLOWED_TRANSITIONS := Map(
        "main->largePopup", true,
        "largePopup->smallPopup", true
    )

    currentProfile := ""
    currentHwnd := 0
    currentPid := 0
    
    armedFrom := ""
    armedTo := ""
    armedTimeoutMs := 0
    armedTime := 0
    
    isLatchedRejected := false
    isCheckpointActive := false
    checkpointProfile := ""
    inputEventCount := 0

    __New(initialProfile := "main", initialHwnd := 0, initialPid := 0) {
        this.currentProfile := initialProfile
        this.currentHwnd := initialHwnd
        this.currentPid := initialPid ? initialPid : ProcessExist()
    }

    /**
     * 전환 대기 활성화
     */
    ArmTransition(fromProfile, toProfile, timeoutMs := 1500) {
        if (this.isLatchedRejected) {
            FileAppend "WINDOW_TRANSITION_REJECTED reason=order_mismatch`n", "*"
            return false
        }

        ; 전환 순서/허용목록 검증
        key := fromProfile "->" toProfile
        if (!WindowTransitionGuardPrototype.ALLOWED_TRANSITIONS.Has(key)) {
            this.Reject("order_mismatch")
            return false
        }

        if (fromProfile != this.currentProfile) {
            this.Reject("order_mismatch")
            return false
        }

        this.armedFrom := fromProfile
        this.armedTo := toProfile
        this.armedTimeoutMs := timeoutMs
        this.armedTime := A_TickCount

        FileAppend "WINDOW_TRANSITION_ARMED from=" fromProfile " to=" toProfile " timeoutMs=" timeoutMs "`n", "*"
        return true
    }

    /**
     * 거부 처리 및 Latch 설정
     */
    Reject(reason) {
        this.isLatchedRejected := true
        this.armedFrom := ""
        this.armedTo := ""
        FileAppend "WINDOW_TRANSITION_REJECTED reason=" reason "`n", "*"
    }

    /**
     * 전환 대상 창 검증 (실제 title/class/PID/client rect 전수 대조)
     */
    ValidateTransition(targetHwnd, expectedProfile) {
        DetectHiddenWindows true
        ; 1. Latch 및 Arm 상태 확인
        if (this.isLatchedRejected || this.armedTo == "") {
            FileAppend "WINDOW_TRANSITION_REJECTED reason=transition_not_armed`n", "*"
            return false
        }

        ; 2. Profile 스키마 존재 여부 확인
        if (!WindowTransitionGuardPrototype.PROFILES.Has(expectedProfile) || expectedProfile != this.armedTo) {
            this.Reject("profile_mismatch")
            return false
        }

        pInfo := WindowTransitionGuardPrototype.PROFILES[expectedProfile]

        ; 3. 대상 창 존재 여부 확인
        hwndNum := Integer(targetHwnd)
        if (!WinExist("ahk_id " hwndNum)) {
            this.Reject("profile_mismatch")
            return false
        }

        ; 4. 실제 Window 속성 추출
        actualTitle := WinGetTitle("ahk_id " hwndNum)
        actualClass := WinGetClass("ahk_id " hwndNum)
        actualPid := WinGetPID("ahk_id " hwndNum)
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwndNum)

        ; 5. 실제 Title 및 Class 검증 (Decoy 차단)
        if (actualTitle != pInfo.title || actualClass != pInfo.winClass) {
            this.Reject("profile_mismatch")
            return false
        }

        ; 6. 실제 경과시간 (Timeout) 검증
        elapsed := A_TickCount - this.armedTime
        if (elapsed > this.armedTimeoutMs) {
            this.Reject("timeout")
            return false
        }

        ; 7. 실제 PID 검증 (별도 프로세스 Decoy 차단)
        if (actualPid != this.currentPid) {
            this.Reject("pid_mismatch")
            return false
        }

        ; 8. Client Size 허용오차 (<= 10px) 검증
        diffW := Abs(cw - pInfo.width)
        diffH := Abs(ch - pInfo.height)
        if (diffW > 10 || diffH > 10) {
            this.Reject("client_size_mismatch")
            return false
        }

        ; 전환 허용 성공
        FileAppend "WINDOW_TRANSITION_ALLOWED from=" this.armedFrom " to=" expectedProfile " samePid=true`n", "*"

        ; 상태 갱신
        this.currentProfile := expectedProfile
        this.currentHwnd := targetHwnd
        this.armedFrom := ""
        this.armedTo := ""

        ; Checkpoint 확인
        if (pInfo.checkpoint) {
            this.isCheckpointActive := true
            this.checkpointProfile := expectedProfile
            FileAppend "CHECKPOINT_REQUIRED profile=" expectedProfile "`n", "*"
        }

        return true
    }

    /**
     * Checkpoint 해제
     */
    ReleaseCheckpoint(profile) {
        if (this.isCheckpointActive && this.checkpointProfile == profile) {
            this.isCheckpointActive := false
            this.checkpointProfile := ""
            FileAppend "CHECKPOINT_RELEASED profile=" profile "`n", "*"
            return true
        }
        return false
    }

    /**
     * 샌드박스 가짜 입력 수행
     */
    PerformSandboxInput(profile) {
        if (this.isCheckpointActive) {
            FileAppend "INPUT_BLOCKED reason=manual_checkpoint profile=" profile "`n", "*"
            return false
        }

        this.inputEventCount++
        FileAppend "SANDBOX_INPUT profile=" profile " count=" this.inputEventCount "`n", "*"
        return true
    }
}
