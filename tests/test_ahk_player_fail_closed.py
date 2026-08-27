# -*- coding: utf-8 -*-
"""
실제 AutoHotkey64 프로세스에서 Player.ahk의 Fail-Closed 안전 차단 동작을 검증하는 테스트
- 1클립 및 다클립 정상 완료 (callback 확인)
- clientResolution 누락 차단
- clientResolution 필드 누락 (width만 있거나 height 누락) 차단
- clientResolution 값 0 이하 차단
- clientResolution 소수(Float) 차단
- clientResolution 숫자형 문자열(String) 차단
- 실제 임시 GUI 창을 생성하고 대상 창 확인 모달 승인 후 client rect 크기 불일치 차단
- screen/client 혼합 모드 차단
- v1 실제입력 차단
- ScaleMode=ratio 차단
"""
import json
import subprocess
import tempfile
from pathlib import Path
import pytest

AHK_EXE = Path(r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe")
ENGINE_DIR = Path(__file__).resolve().parent.parent / "도구" / "엔진"

def run_ahk_macro_test(macro_dict, cfg_dict=None, custom_harness_setup=""):
    """임시 JSON 및 AHK 하네스를 생성해 실행 결과를 반환 (timeout 시 확실한 프로세스/파일 정리)"""
    cfg = {
        "dryRun": True,
        "quiet": True,
        "pasteMode": True,
        "defaultIntervalMs": 1,
        "restoreOnStop": False,
        "targetTitle": "",
        "targetClass": "",
        "targetExe": "",
        "scaleMode": "off",
        "baseWidth": 1920,
        "baseHeight": 1080
    }
    if cfg_dict:
        cfg.update(cfg_dict)

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", encoding="utf-8", delete=False) as fj:
        json.dump(macro_dict, fj, ensure_ascii=False)
        json_path = fj.name

    harness_code = f"""
#Requires AutoHotkey v2.0
#SingleInstance Force

#Include {ENGINE_DIR}\\Lib\\Json.ahk
#Include {ENGINE_DIR}\\Lib\\Player.ahk

{custom_harness_setup}

cfg := {{
    dryRun: {"true" if cfg["dryRun"] else "false"},
    quiet: {"true" if cfg["quiet"] else "false"},
    pasteMode: {"true" if cfg["pasteMode"] else "false"},
    defaultIntervalMs: {cfg["defaultIntervalMs"]},
    restoreOnStop: {"true" if cfg["restoreOnStop"] else "false"},
    targetTitle: "{cfg["targetTitle"]}",
    targetClass: "{cfg["targetClass"]}",
    targetExe: "{cfg["targetExe"]}",
    scaleMode: "{cfg["scaleMode"]}",
    baseWidth: {cfg["baseWidth"]},
    baseHeight: {cfg["baseHeight"]}
}}

jsonPath := "{json_path.replace('\\', '\\\\')}"
macro := JsonParser.Load(FileRead(jsonPath, "UTF-8"))
p := Player(macro, cfg)

callbackCalled := false
callbackReason := ""

OnDone(reason) {{
    global callbackCalled, callbackReason
    callbackCalled := true
    callbackReason := reason
    FileAppend "CALLBACK_TRIGGERED: " reason "`n", "*"
}}

p.onStop := OnDone
ok := p.PrepareTarget()
if (!ok) {{
    for logLine in p.logs
        FileAppend logLine "`n", "*"
    FileAppend "PREPARE_REJECTED`n", "*"
    ExitApp 10
}}

p.StartOrResume()
loopCount := 0
while (p.state = Player.RUNNING && loopCount < 1000) {{
    p.nextAt := 0
    p.Tick()
    loopCount++
}}

if (p.state = Player.STOPPED && callbackCalled) {{
    FileAppend "COMPLETED_OK`n", "*"
    ExitApp 0
}} else {{
    for logLine in p.logs
        FileAppend logLine "`n", "*"
    FileAppend "STOPPED_OR_FAILED: state=" p.state "`n", "*"
    ExitApp 1
}}
"""

    with tempfile.NamedTemporaryFile(mode="w", suffix=".ahk", encoding="utf-8-sig", delete=False) as fa:
        fa.write(harness_code)
        ahk_path = fa.name

    proc = None
    try:
        cmd = [str(AHK_EXE), "/ErrorStdOut", ahk_path]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout_bytes, stderr_bytes = proc.communicate(timeout=6)
        stdout_str = stdout_bytes.decode("cp949", errors="replace")
        stderr_str = stderr_bytes.decode("cp949", errors="replace")
        
        class SimpleResult:
            def __init__(self, ret, out, err):
                self.returncode = ret
                self.stdout = out
                self.stderr = err

        return SimpleResult(proc.returncode, stdout_str, stderr_str)
    except subprocess.TimeoutExpired:
        if proc:
            proc.kill()
            proc.communicate()
        raise
    finally:
        try:
            Path(json_path).unlink()
            Path(ahk_path).unlink()
        except OSError:
            pass


def test_single_and_multi_clip_completion():
    """1클립 및 3클립 매크로가 정상 실행되고 onStop 콜백을 호출하며 종료되는지 검증"""
    macro = {
        "format": "regimacro",
        "version": 2,
        "sections": [
            {
                "id": "sec_1",
                "label": "구간 1",
                "clips": [
                    {"type": "key", "key": "TAB"},
                    {"type": "text", "value": "테스트입력"},
                    {"type": "key", "key": "ENTER"}
                ]
            }
        ]
    }
    res = run_ahk_macro_test(macro, {"dryRun": True})
    assert res.returncode == 0
    assert "CALLBACK_TRIGGERED: 재생 완료" in res.stdout
    assert "COMPLETED_OK" in res.stdout


def test_client_resolution_missing_rejected():
    """client 클립이 있으나 clientResolution 메타데이터가 누락된 경우 사전 차단 검증"""
    macro = {
        "format": "regimacro",
        "version": 2,
        "sections": [
            {
                "id": "sec_1",
                "clips": [
                    {"type": "mouse", "coordMode": "client", "x": 100, "y": 100}
                ]
            }
        ]
    }
    res = run_ahk_macro_test(macro, {"dryRun": True})
    assert res.returncode == 10  # PREPARE_REJECTED
    assert "PREPARE_REJECTED" in res.stdout
    assert "clientResolution 메타데이터 누락" in res.stdout


def test_client_resolution_field_missing_rejected():
    """clientResolution에 height 필드가 누락된 경우 차단 검증"""
    macro = {
        "format": "regimacro",
        "version": 2,
        "clientResolution": {"width": 1920},
        "sections": [
            {
                "id": "sec_1",
                "clips": [
                    {"type": "mouse", "coordMode": "client", "x": 100, "y": 100}
                ]
            }
        ]
    }
    res = run_ahk_macro_test(macro, {"dryRun": True})
    assert res.returncode == 10
    assert "PREPARE_REJECTED" in res.stdout
    assert "필드 누락" in res.stdout


def test_client_resolution_zero_rejected():
    """clientResolution의 width가 0인 경우 차단 검증"""
    macro = {
        "format": "regimacro",
        "version": 2,
        "clientResolution": {"width": 0, "height": 1080},
        "sections": [
            {
                "id": "sec_1",
                "clips": [
                    {"type": "mouse", "coordMode": "client", "x": 100, "y": 100}
                ]
            }
        ]
    }
    res = run_ahk_macro_test(macro, {"dryRun": True})
    assert res.returncode == 10
    assert "PREPARE_REJECTED" in res.stdout
    assert "형식 오류" in res.stdout


def test_client_resolution_float_rejected():
    """clientResolution에 소수(Float)가 입력된 경우 차단 검증"""
    macro = {
        "format": "regimacro",
        "version": 2,
        "clientResolution": {"width": 1920.5, "height": 1080},
        "sections": [
            {
                "id": "sec_1",
                "clips": [
                    {"type": "mouse", "coordMode": "client", "x": 100, "y": 100}
                ]
            }
        ]
    }
    res = run_ahk_macro_test(macro, {"dryRun": True})
    assert res.returncode == 10
    assert "PREPARE_REJECTED" in res.stdout
    assert "형식 오류" in res.stdout


def test_client_resolution_string_rejected():
    """clientResolution에 숫자형 문자열(String)이 입력된 경우 차단 검증"""
    macro = {
        "format": "regimacro",
        "version": 2,
        "clientResolution": {"width": "1920", "height": "1080"},
        "sections": [
            {
                "id": "sec_1",
                "clips": [
                    {"type": "mouse", "coordMode": "client", "x": 100, "y": 100}
                ]
            }
        ]
    }
    res = run_ahk_macro_test(macro, {"dryRun": True})
    assert res.returncode == 10
    assert "PREPARE_REJECTED" in res.stdout
    assert "형식 오류" in res.stdout


def test_client_size_mismatch_with_real_gui_rejected():
    """
    실제 임시 GUI 창(800x600)을 띄우고 targetTitle로 지정한 뒤,
    Player.PrepareTarget()에서 실제 client rect(800x600)와 매크로(1920x1080) 비교 불일치 분기에 도달하여
    로그에 'Client 크기 불일치'가 남고 차단(Exit 10)되는지 검증
    """
    macro = {
        "format": "regimacro",
        "version": 2,
        "clientResolution": {"width": 1920, "height": 1080},
        "sections": [
            {
                "id": "sec_1",
                "clips": [
                    {"type": "mouse", "coordMode": "client", "x": 100, "y": 100}
                ]
            }
        ]
    }
    gui_setup = """
; 임시 타겟 GUI 생성 및 표시
testGui := Gui("+AlwaysOnTop", "TestTargetClientWindow")
testGui.Show("w800 h600")
WinActivate("ahk_id " testGui.Hwnd)

; 제품 코드의 사용자 확인 안전장치는 유지하고, 시험 하네스가 Yes를 실제 클릭
AutoConfirmTarget(*) {
    if (dlg := WinExist("RegiMacro 대상 창 확정")) {
        ControlClick "Button1", "ahk_id " dlg
        ; 창이 실제 닫힌 경우에만 성공 처리하고, 아니면 다음 타이머 tick에서 재시도
        if WinWaitClose("ahk_id " dlg, , 0.5) {
            FileAppend "CONFIRM_AUTO_YES`n", "*"
            SetTimer AutoConfirmTarget, 0
        }
    }
}
SetTimer AutoConfirmTarget, 50
Sleep 100
"""
    res = run_ahk_macro_test(
        macro,
        {"dryRun": False, "quiet": True, "targetTitle": "TestTargetClientWindow"},
        custom_harness_setup=gui_setup
    )
    assert res.returncode == 10
    assert "CONFIRM_AUTO_YES" in res.stdout
    assert "PREPARE_REJECTED" in res.stdout
    assert "Client 크기 불일치" in res.stdout


def test_mixed_screen_and_client_rejected():
    """단일 매크로 내에 screen과 client 좌표계가 혼합된 경우 Fail-Closed 차단 검증"""
    macro = {
        "format": "regimacro",
        "version": 2,
        "clientResolution": {"width": 1920, "height": 1080},
        "sections": [
            {
                "id": "sec_1",
                "clips": [
                    {"type": "mouse", "coordMode": "screen", "x": 100, "y": 100},
                    {"type": "mouse", "coordMode": "client", "x": 200, "y": 200}
                ]
            }
        ]
    }
    res = run_ahk_macro_test(macro, {"dryRun": True})
    assert res.returncode == 10
    assert "PREPARE_REJECTED" in res.stdout
    assert "screen/client 혼합" in res.stdout


def test_v1_actual_input_rejected():
    """v1 스키마의 실제 입력 시도 시 즉시 차단 검증"""
    macro = {
        "format": "regimacro",
        "version": 1,
        "sections": [
            {
                "id": "sec_1",
                "clips": [{"type": "key", "key": "TAB"}]
            }
        ]
    }
    res = run_ahk_macro_test(macro, {"dryRun": False, "quiet": True})
    assert res.returncode == 10
    assert "PREPARE_REJECTED" in res.stdout
    assert "v1 스키마 실제입력 차단" in res.stdout


def test_scalemode_ratio_rejected():
    """ScaleMode=ratio 실제 입력 시도 시 즉시 차단 검증"""
    macro = {
        "format": "regimacro",
        "version": 2,
        "sections": [
            {
                "id": "sec_1",
                "clips": [{"type": "mouse", "coordMode": "screen", "x": 100, "y": 100}]
            }
        ]
    }
    res = run_ahk_macro_test(macro, {"dryRun": False, "quiet": True, "scaleMode": "ratio"})
    assert res.returncode == 10
    assert "PREPARE_REJECTED" in res.stdout
    assert "ScaleMode=ratio 실행 차단" in res.stdout
