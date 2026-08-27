import json
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
CONVERTER = ROOT / "도구" / "wem변환기.ps1"
POWERSHELL = shutil.which("powershell") or shutil.which("pwsh")


def run_converter(tmp_path: Path, name: str, tokens: list[str]):
    if not POWERSHELL:
        pytest.skip("PowerShell is not available")
    wem = tmp_path / f"{name}.wem"
    out = tmp_path / "out"
    wem.write_text("|".join(tokens), encoding="utf-8")
    proc = subprocess.run(
        [
            POWERSHELL,
            "-NoProfile",
            "-File",
            str(CONVERTER),
            "-WemPath",
            str(wem),
            "-OutDir",
            str(out),
        ],
        capture_output=True,
        text=True,
        encoding="cp949",
        errors="replace",
    )
    return proc, out / f"{name}_초안.json"


def test_right_monitor_import_is_normalized_to_schema_v2(tmp_path):
    proc, output = run_converter(
        tmp_path,
        "right",
        ["[2176,597]", "Down", "Up", "[3691,1003]", "Down", "Up"],
    )

    assert proc.returncode == 0, proc.stdout + proc.stderr
    data = json.loads(output.read_text(encoding="utf-8-sig"))
    assert data["version"] == 2
    assert data["baseResolution"] == {"width": 1920, "height": 1080}
    assert data["source"]["recordedSegment"] == "right"
    assert data["source"]["originalSpan"] == "dual-fhd-3840x1080"
    assert data["source"]["coordinateNormalization"] == "monitor-local"
    clips = [clip for sec in data["sections"] for clip in sec["clips"]]
    assert [(clip["x"], clip["y"]) for clip in clips] == [(256, 597), (1771, 1003)]
    assert all(clip["coordMode"] == "screen" for clip in clips)
    assert all(sec["id"] == f"sec_{idx}" for idx, sec in enumerate(data["sections"], 1))
    report = output.with_suffix(".md").read_text(encoding="utf-8-sig")
    assert "원본 모니터: right" in report
    assert "단일 FHD 1920×1080 내부좌표로 정규화" in report


def test_left_monitor_import_preserves_monitor_local_x(tmp_path):
    proc, output = run_converter(
        tmp_path,
        "left",
        ["[103,177]", "Down", "Up", "[1745,1013]", "Down", "Up"],
    )

    assert proc.returncode == 0, proc.stdout + proc.stderr
    data = json.loads(output.read_text(encoding="utf-8-sig"))
    assert data["source"]["recordedSegment"] == "left"
    clips = [clip for sec in data["sections"] for clip in sec["clips"]]
    assert [(clip["x"], clip["y"]) for clip in clips] == [(103, 177), (1745, 1013)]


def test_mixed_monitor_clicks_are_rejected(tmp_path):
    proc, output = run_converter(
        tmp_path,
        "mixed",
        ["[100,100]", "Down", "Up", "[2100,100]", "Down", "Up"],
    )

    assert proc.returncode != 0
    assert not output.exists()
    assert "여러 모니터" in proc.stdout + proc.stderr
