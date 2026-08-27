#Requires AutoHotkey v2.0
#SingleInstance Off
DetectHiddenWindows true
SetTitleMatchMode 2

#Include WindowTransitionGuardPrototype.ahk

if (A_Args.Length < 1) {
    FileAppend "Usage: window_transition_sandbox.ahk <test_name>`n", "*"
    ExitApp 1
}

testName := A_Args[1]

; GUI 객체 관리 (전역 변수)
global guiMain := 0
global guiLarge := 0
global guiSmall := 0
global guiDecoy := 0

CreateGui(profile, extraW := 0, extraH := 0, customTitle := "") {
    global guiMain, guiLarge, guiSmall, guiDecoy
    pInfo := WindowTransitionGuardPrototype.PROFILES[profile]
    w := pInfo.width + extraW
    h := pInfo.height + extraH
    t := customTitle != "" ? customTitle : pInfo.title
    g := Gui("+AlwaysOnTop", t)
    g.Show("w" w " h" h)
    WinActivate("ahk_id " g.Hwnd)
    Sleep 50
    return g
}

CleanGuis() {
    global guiMain, guiLarge, guiSmall, guiDecoy
    if (guiMain) {
        guiMain.Destroy()
        guiMain := 0
    }
    if (guiLarge) {
        guiLarge.Destroy()
        guiLarge := 0
    }
    if (guiSmall) {
        guiSmall.Destroy()
        guiSmall := 0
    }
    if (guiDecoy) {
        guiDecoy.Destroy()
        guiDecoy := 0
    }
}

try {
    if (testName == "test_main_to_large_same_pid_allowed") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        ok := guard.ArmTransition("main", "largePopup", 1500)
        if (!ok)
            ExitApp 10
        
        guiLarge := CreateGui("largePopup")
        ok := guard.ValidateTransition(guiLarge.Hwnd, "largePopup")
        if (!ok)
            ExitApp 11
        ExitApp 0
    }
    else if (testName == "test_large_to_small_same_pid_allowed") {
        guiLarge := CreateGui("largePopup")
        guard := WindowTransitionGuardPrototype("largePopup", guiLarge.Hwnd)
        
        ok := guard.ArmTransition("largePopup", "smallPopup", 1500)
        if (!ok)
            ExitApp 10
        
        guiSmall := CreateGui("smallPopup")
        ok := guard.ValidateTransition(guiSmall.Hwnd, "smallPopup")
        if (!ok)
            ExitApp 11
        ExitApp 0
    }
    else if (testName == "test_transition_without_arm_rejected_exact_reason") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        guiLarge := CreateGui("largePopup")
        ok := guard.ValidateTransition(guiLarge.Hwnd, "largePopup")
        if (!ok)
            ExitApp 10
        ExitApp 0
    }
    else if (testName == "test_same_pid_wrong_title_rejected_exact_reason") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        guard.ArmTransition("main", "largePopup", 1500)
        ; 같은 PID이지만 제목이 잘못된 창 (UNLISTED DECOY)
        guiDecoy := CreateGui("largePopup", 0, 0, "UNLISTED DECOY")
        ok := guard.ValidateTransition(guiDecoy.Hwnd, "largePopup")
        if (!ok)
            ExitApp 10
        ExitApp 0
    }
    else if (testName == "test_wrong_expected_class_rejected_exact_reason") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        guard.ArmTransition("main", "largePopup", 1500)
        guiLarge := CreateGui("largePopup")
        ; 허용되지 않은 profile
        ok := guard.ValidateTransition(guiLarge.Hwnd, "invalidClassProfile")
        if (!ok)
            ExitApp 10
        ExitApp 0
    }
    else if (testName == "test_same_title_class_different_pid_rejected_exact_reason") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        guard.ArmTransition("main", "largePopup", 1500)
        
        ; 별도 AHK 프로세스로 동일 Title/Class/Size Decoy GUI 실행
        decoyScript := A_ScriptDir "\decoy_server.ahk"
        Run(Format('"{1}" /ErrorStdOut "{2}"', A_AhkPath, decoyScript), , , &decoyPid)
        decoyHwnd := WinWait("RegiMacro Sandbox Large ahk_pid " decoyPid,, 3)
        if (!decoyHwnd) {
            FileAppend "ERROR: Decoy window not found`n", "*"
            ExitApp 1
        }
        
        ok := guard.ValidateTransition(decoyHwnd, "largePopup")
        ProcessClose(decoyPid)
        if (!ok)
            ExitApp 10
        ExitApp 0
    }
    else if (testName == "test_transition_timeout_rejected_exact_reason") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        ; 타임아웃 200ms 설정 후 실제 Sleep 300ms 경과
        guard.ArmTransition("main", "largePopup", 200)
        Sleep 300
        
        guiLarge := CreateGui("largePopup")
        ok := guard.ValidateTransition(guiLarge.Hwnd, "largePopup")
        if (!ok)
            ExitApp 10
        ExitApp 0
    }
    else if (testName == "test_transition_order_skip_rejected_exact_reason") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        ; main -> smallPopup 순서 건너뛰기
        ok := guard.ArmTransition("main", "smallPopup", 1500)
        if (!ok)
            ExitApp 10
        ExitApp 0
    }
    else if (testName == "test_client_size_plus_10_allowed") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        guard.ArmTransition("main", "largePopup", 1500)
        guiLarge := CreateGui("largePopup", 10, 10)
        ok := guard.ValidateTransition(guiLarge.Hwnd, "largePopup")
        if (!ok)
            ExitApp 11
        ExitApp 0
    }
    else if (testName == "test_client_size_plus_11_rejected_exact_reason") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        guard.ArmTransition("main", "largePopup", 1500)
        guiLarge := CreateGui("largePopup", 11, 11)
        ok := guard.ValidateTransition(guiLarge.Hwnd, "largePopup")
        if (!ok)
            ExitApp 10
        ExitApp 0
    }
    else if (testName == "test_manual_checkpoint_blocks_input_until_release") {
        guiLarge := CreateGui("largePopup")
        guard := WindowTransitionGuardPrototype("largePopup", guiLarge.Hwnd)
        
        guard.ArmTransition("largePopup", "smallPopup", 1500)
        guiSmall := CreateGui("smallPopup")
        guard.ValidateTransition(guiSmall.Hwnd, "smallPopup")
        
        ; 1. Checkpoint 활성 상태에서 입력 차단
        ok1 := guard.PerformSandboxInput("smallPopup")
        
        ; 2. Checkpoint 해제
        guard.ReleaseCheckpoint("smallPopup")
        
        ; 3. Checkpoint 해제 후 1회 입력 허용
        ok2 := guard.PerformSandboxInput("smallPopup")
        
        if (!ok1 && ok2)
            ExitApp 0
        else
            ExitApp 12
    }
    else if (testName == "test_rejection_latches_guard_and_prevents_retry") {
        guiMain := CreateGui("main")
        guard := WindowTransitionGuardPrototype("main", guiMain.Hwnd)
        
        ; 1. Arm 후 잘못된 창으로 1차 거부 유발
        guard.ArmTransition("main", "largePopup", 1500)
        guiDecoy := CreateGui("largePopup", 0, 0, "UNLISTED DECOY")
        guard.ValidateTransition(guiDecoy.Hwnd, "largePopup")
        
        ; 2. 거부 후 정상 창으로 재시도해도 Latch되어 차단되는지 검증
        guiLarge := CreateGui("largePopup")
        ok2 := guard.ValidateTransition(guiLarge.Hwnd, "largePopup")
        if (!ok2)
            ExitApp 10
        ExitApp 0
    }
    else if (testName == "test_cleanup_leaves_no_spawned_sandbox_process") {
        guiMain := CreateGui("main")
        ExitApp 0
    }
    else {
        FileAppend "Unknown test name: " testName "`n", "*"
        ExitApp 1
    }
} catch as err {
    FileAppend "CATCH_ERR: " err.Message "`n" err.Stack "`n", "*"
    ExitApp 99
} finally {
    CleanGuis()
}
