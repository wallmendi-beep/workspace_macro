# -*- coding: utf-8 -*-
"""
Player Core 상태머신, DryRun 전 스텝 순회 시뮬레이션 및 Fail-Closed 안전장치 전수 검증
"""
import json
from pathlib import Path
import pytest

RESULT_DIR = Path(__file__).resolve().parent.parent / "변환 결과"
JSON_FILES = list(RESULT_DIR.glob("*_초안.json"))

class MockPlayerEngine:
    """Player.ahk의 로직을 정확히 재현한 시뮬레이션 엔진 (단위/회귀 시험용)"""
    def __init__(self, macro_data, cfg=None):
        self.macro = macro_data
        self.cfg = cfg or {"dryRun": True, "scaleMode": "off", "baseWidth": 1920, "baseHeight": 1080}
        self.version = self.macro.get("version", 1)
        
        self.steps = []
        for s_idx, sec in enumerate(self.macro.get("sections", []), 1):
            for c_idx, clip in enumerate(sec.get("clips", []), 1):
                self.steps.append({"s": s_idx, "c": c_idx, "clip": clip})

        self.step_idx = 0
        self.state = "정지"
        self.logs = []
        self.target_mon = 1
        self.mon_left = 0
        self.mon_top = 0
        self.mon_right = 1920
        self.mon_bottom = 1080
        self.mon_origin_x = 0
        self.mon_origin_y = 0

    def prepare_target(self, is_active_window=True, title="등기시스템", cfg_target_title="", is_maximized=True):
        # 1. v1 실제입력 차단
        if self.version < 2 and not self.cfg.get("dryRun"):
            self.logs.append("[오류] v1 스키마 실제입력 차단")
            return False

        # 2. ScaleMode 검증
        if not self.cfg.get("dryRun") and self.cfg.get("scaleMode") != "off":
            self.logs.append(f"[오류] ScaleMode={self.cfg.get('scaleMode')} 실행 차단")
            return False

        # 3. 대상 창 활성 검증
        if not is_active_window:
            self.logs.append("[오류] 활성화된 Foreground 창 없음")
            return False

        if cfg_target_title and cfg_target_title not in title:
            self.logs.append(f"[오류] 대상 창 제목 불일치: {title}")
            return False

        # 4. 최대화 검증
        has_screen_clip = any(s["clip"].get("type") == "mouse" and s["clip"].get("coordMode") == "screen" for s in self.steps)
        if has_screen_clip and not self.cfg.get("dryRun"):
            if not is_maximized:
                self.logs.append("[오류] 최대화 실패/불일치로 차단")
                return False

        return True

    def execute_step(self, step, active_hwnd=1, target_hwnd=1):
        clip = step["clip"]
        t = clip.get("type")

        # 포커스 이탈 가드
        if not self.cfg.get("dryRun"):
            if active_hwnd != target_hwnd:
                self.state = "정지"
                self.logs.append("[오류] 포커스 이탈 — 대상 창 비활성화로 입력 차단")
                return False

        if t == "mouse":
            raw_x = clip.get("x", 0)
            raw_y = clip.get("y", 0)
            cm = clip.get("coordMode", "screen")

            if cm == "screen":
                final_x = self.mon_origin_x + raw_x
                final_y = self.mon_origin_y + raw_y

                # Fail-Closed 모니터 범위 검증
                if final_x < self.mon_left or final_x >= self.mon_right or final_y < self.mon_top or final_y >= self.mon_bottom:
                    self.state = "정지"
                    self.logs.append(f"[오류] 좌표 이탈 ({final_x}, {final_y}) 차단")
                    return False

                self.logs.append(f"[모의] 클릭 ({raw_x}, {raw_y}) -> screen({final_x}, {final_y})")
            else:
                self.logs.append(f"[모의] 클릭 ({raw_x}, {raw_y}) -> client({raw_x}, {raw_y})")

        elif t == "key":
            self.logs.append(f"[모의] 키: {clip.get('key')}")
        elif t == "text":
            self.logs.append(f"[모의] 입력: {clip.get('value', '')}")

        return True

    def run_dryrun_all(self):
        assert self.prepare_target() is True
        self.state = "실행중"
        for s in self.steps:
            ok = self.execute_step(s)
            if not ok:
                return False
        self.state = "정지"
        return True


@pytest.mark.parametrize("json_path", JSON_FILES, ids=lambda p: p.stem)
def test_player_dryrun_full_cycle(json_path):
    """6종 JSON 파일에 대해 Player가 전 스텝을 100% 정상 순회하는지 검증"""
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    engine = MockPlayerEngine(data, cfg={"dryRun": True, "scaleMode": "off"})
    assert engine.run_dryrun_all() is True
    assert len(engine.logs) > 0
    assert engine.state == "정지"


def test_fail_closed_v1_actual_input_rejected():
    """v1 스키마의 실제 입력 거부 검증"""
    v1_macro = {"format": "regimacro", "version": 1, "sections": [{"clips": [{"type": "key", "key": "TAB"}]}]}
    engine = MockPlayerEngine(v1_macro, cfg={"dryRun": False, "scaleMode": "off"})
    assert engine.prepare_target() is False
    assert any("v1 스키마 실제입력 차단" in log for log in engine.logs)


def test_fail_closed_scalemode_ratio_rejected():
    """v2 유산 매크로의 ScaleMode=ratio 실제 입력 거부 검증"""
    v2_macro = {"format": "regimacro", "version": 2, "sections": [{"clips": [{"type": "mouse", "coordMode": "screen", "x": 100, "y": 100}]}]}
    engine = MockPlayerEngine(v2_macro, cfg={"dryRun": False, "scaleMode": "ratio"})
    assert engine.prepare_target() is False
    assert any("ScaleMode=ratio 실행 차단" in log for log in engine.logs)


def test_fail_closed_target_title_mismatch():
    """대상 창 제목 불일치 시 실행 차단 검증"""
    v2_macro = {"format": "regimacro", "version": 2, "sections": [{"clips": [{"type": "key", "key": "TAB"}]}]}
    engine = MockPlayerEngine(v2_macro, cfg={"dryRun": False, "scaleMode": "off"})
    assert engine.prepare_target(title="메모장", cfg_target_title="등기시스템") is False
    assert any("대상 창 제목 불일치" in log for log in engine.logs)


def test_fail_closed_focus_loss_guard():
    """실행 도중 포커스 이탈 시 즉시 입력 차단 검증"""
    v2_macro = {"format": "regimacro", "version": 2, "sections": [{"clips": [{"type": "key", "key": "TAB"}]}]}
    engine = MockPlayerEngine(v2_macro, cfg={"dryRun": False, "scaleMode": "off"})
    step = {"clip": {"type": "key", "key": "TAB"}}
    assert engine.execute_step(step, active_hwnd=999, target_hwnd=1) is False
    assert any("포커스 이탈" in log for log in engine.logs)


def test_fail_closed_coordinate_out_of_bounds():
    """마우스 좌표가 모니터 경계를 벗어날 때 차단 검증"""
    v2_macro = {"format": "regimacro", "version": 2, "sections": []}
    engine = MockPlayerEngine(v2_macro, cfg={"dryRun": False, "scaleMode": "off"})
    step = {"clip": {"type": "mouse", "coordMode": "screen", "x": 2500, "y": 500}}
    assert engine.execute_step(step) is False
    assert any("좌표 이탈" in log for log in engine.logs)
