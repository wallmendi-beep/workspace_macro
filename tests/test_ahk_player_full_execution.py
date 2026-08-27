# -*- coding: utf-8 -*-
"""
실제 AutoHotkey64 프로세스에서 Player.ahk를 구동하여
6종 JSON의 모든 클립을 Tick() 순회하고 onStop 콜백 및 정상 종료를 검증하는 테스트
"""
import subprocess
import tempfile
from pathlib import Path
import pytest

AHK_EXE = Path(r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe")
ENGINE_DIR = Path(__file__).resolve().parent.parent / "도구" / "엔진"
RESULT_DIR = Path(__file__).resolve().parent.parent / "변환 결과"
JSON_FILES = list(RESULT_DIR.glob("*_초안.json"))

AHK_HARNESS_TEMPLATE = r"""
#Requires AutoHotkey v2.0
#SingleInstance Force

#Include {engine_dir}\Lib\Json.ahk
#Include {engine_dir}\Lib\Player.ahk

cfg := {{
    dryRun: true,
    quiet: true,
    pasteMode: true,
    defaultIntervalMs: 1,
    restoreOnStop: false,
    targetTitle: "",
    targetClass: "",
    targetExe: "",
    scaleMode: "off",
    baseWidth: 1920,
    baseHeight: 1080
}}

jsonPath := "{json_path}"
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

; 재생 시작
p.StartOrResume()

; 전 스텝 순회
loopCount := 0
while (p.state = Player.RUNNING && loopCount < 5000) {{
    p.nextAt := 0
    p.Tick()
    loopCount++
}}

if (p.state = Player.STOPPED && callbackCalled) {{
    FileAppend "PLAYER_AHK_ALL_STEPS_COMPLETED: " p.TotalSteps() " steps, loop: " loopCount "`n", "*"
    ExitApp 0
}} else {{
    FileAppend "PLAYER_AHK_FAILED: state=" p.state ", callback=" callbackCalled ", loop=" loopCount "`n", "*"
    ExitApp 1
}}
"""

@pytest.mark.parametrize("json_path", JSON_FILES, ids=lambda p: p.stem)
def test_ahk_player_full_execution_with_callback(json_path):
    """
    실제 AutoHotkey64 프로세스에서 Player.ahk를 include하여
    6종 JSON의 모든 클립을 Tick() 순회하고 onStop 콜백 및 정상 종료(Exit 0) 검증
    """
    harness_code = AHK_HARNESS_TEMPLATE.format(
        engine_dir=str(ENGINE_DIR).replace("\\", "\\\\"),
        json_path=str(json_path).replace("\\", "\\\\")
    )

    with tempfile.NamedTemporaryFile(mode="w", suffix=".ahk", encoding="utf-8-sig", delete=False) as f:
        f.write(harness_code)
        temp_ahk_path = f.name

    try:
        cmd = [str(AHK_EXE), "/ErrorStdOut", temp_ahk_path]
        res = subprocess.run(cmd, capture_output=True, encoding="cp949", errors="replace", timeout=10)

        assert res.returncode == 0, f"AHK Player 실행 실패 (Exit: {res.returncode})\nStderr: {res.stderr}\nStdout: {res.stdout}"
        assert "CALLBACK_TRIGGERED: 재생 완료" in res.stdout
        assert "PLAYER_AHK_ALL_STEPS_COMPLETED:" in res.stdout
    finally:
        try:
            Path(temp_ahk_path).unlink()
        except OSError:
            pass
