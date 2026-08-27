# -*- coding: utf-8 -*-
"""
Core 재생 엔진 및 스키마 v2 산출물 교차 검증 테스트
"""
import json
from pathlib import Path
import pytest

RESULT_DIR = Path(__file__).resolve().parent.parent / "변환 결과"
JSON_FILES = list(RESULT_DIR.glob("*_초안.json"))

def test_json_files_count():
    """6종의 JSON 파일이 모두 존재하는지 확인"""
    assert len(JSON_FILES) == 6, f"예상 파일 수 6개, 실제: {len(JSON_FILES)}"

@pytest.mark.parametrize("json_path", JSON_FILES, ids=lambda p: p.stem)
def test_schema_v2_compliance(json_path):
    """6종 JSON 파일의 스키마 v2 규격 및 정규화 좌표 검증"""
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 1. 기본 메타데이터
    assert data.get("format") == "regimacro"
    assert data.get("version") == 2, f"{json_path.name} version != 2"
    assert data.get("baseResolution") == {"width": 1920, "height": 1080}
    
    # 2. Source 메타데이터
    source = data.get("source", {})
    assert source.get("type") == "wem-import"
    assert source.get("recordedSegment") in ("left", "right")
    assert source.get("originalSpan") == "dual-fhd-3840x1080"
    assert source.get("coordinateNormalization") == "monitor-local"

    # 3. 구간 및 클립 검증
    sections = data.get("sections", [])
    assert len(sections) > 0, "구간이 비어있음"

    total_clips = 0
    for s_idx, sec in enumerate(sections, 1):
        assert sec.get("id") == f"sec_{s_idx}"
        clips = sec.get("clips", [])
        assert len(clips) > 0, f"구간 {s_idx}의 클립이 비어있음"
        
        for c in clips:
            total_clips += 1
            c_type = c.get("type")
            assert c_type in ("mouse", "key", "text"), f"알 수 없는 클립 타입: {c_type}"
            
            if c_type == "mouse":
                assert c.get("coordMode") == "screen"
                x = c.get("x")
                y = c.get("y")
                assert isinstance(x, int) and isinstance(y, int)
                # 정규화 좌표 0 <= x < 1920, 0 <= y < 1080 범위 검증
                assert 0 <= x < 1920, f"x 좌표 ({x}) 범위 이탈: {json_path.name}"
                assert 0 <= y < 1080, f"y 좌표 ({y}) 범위 이탈: {json_path.name}"

    assert total_clips > 0
