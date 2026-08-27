# -*- coding: utf-8 -*-
"""
AutoHotkey v2 Core 엔진 실제 기동 및 6종 JSON 정상 상주 검증 테스트
"""
import subprocess
import time
from pathlib import Path
import pytest

AHK_EXE = Path(r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe")
SCRIPT_PATH = Path(__file__).resolve().parent.parent / "도구" / "엔진" / "RegiMacro.ahk"
RESULT_DIR = Path(__file__).resolve().parent.parent / "변환 결과"
JSON_FILES = list(RESULT_DIR.glob("*_초안.json"))

def test_ahk_executable_exists():
    assert AHK_EXE.exists(), f"AutoHotkey64.exe를 찾을 수 없습니다: {AHK_EXE}"

@pytest.mark.parametrize("json_path", JSON_FILES, ids=lambda p: p.stem)
def test_regimacro_startup_and_resident(json_path):
    """
    각 6종 JSON에 대해 RegiMacro.ahk가 에러 없이 정상 기동되고
    UI와 타이머가 상주 상태를 유지하는지 실제 프로세스를 띄워 검증.
    """
    cmd = [str(AHK_EXE), "/ErrorStdOut", str(SCRIPT_PATH), str(json_path)]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    try:
        # 프로세스 기동 및 초기화 대기 (1.5초)
        time.sleep(1.5)
        poll = proc.poll()

        if poll is not None:
            stdout, stderr = proc.communicate(timeout=1)
            pytest.fail(f"RegiMacro 기동 즉시 종료 (Exit Code: {poll})\nStderr: {stderr}\nStdout: {stdout}")
        
        # 정상 상주 확인됨 -> 테스트 성공
        assert proc.poll() is None, "프로세스가 정상 상주 상태여야 함"
    finally:
        # 테스트 종료 후 프로세스 정리
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
