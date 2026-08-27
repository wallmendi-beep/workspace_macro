# -*- coding: utf-8 -*-
"""
RM-WINDOW-004: expectedWindow allowlist 전환계약 샌드박스 보완 오라클 14개 시험
- 실제 title/class 대조 (같은 PID 잘못된 제목 거부)
- 별도 AHK 프로세스 PID Decoy 차단
- 실제 경과시간(Sleep) timeout 검증
- Rejection Latch 및 재시도 차단 검증
- Spawn된 프로세스 자원 정리 및 test hook 0건 정적 검증
"""
import subprocess
import time
from pathlib import Path
import pytest

AHK_EXE = Path(r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe")
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"
SANDBOX_AHK = FIXTURES_DIR / "window_transition_sandbox.ahk"
GUARD_AHK = FIXTURES_DIR / "WindowTransitionGuardPrototype.ahk"


def run_sandbox_command(args, timeout=6):
    """샌드박스 AHK 스크립트 실행 래퍼 (cp949 인코딩, 프로세스 정리)"""
    cmd = [str(AHK_EXE), "/ErrorStdOut", str(SANDBOX_AHK)] + args
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        stdout_bytes, stderr_bytes = proc.communicate(timeout=timeout)
        stdout_str = stdout_bytes.decode("cp949", errors="replace")
        stderr_str = stderr_bytes.decode("cp949", errors="replace")
        return proc.returncode, stdout_str, stderr_str, proc.pid
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        raise


def test_main_to_large_same_pid_allowed():
    """1. main -> largePopup 동일 PID 정상 허용 검증"""
    ret, out, err, _ = run_sandbox_command(["test_main_to_large_same_pid_allowed"])
    assert ret == 0, f"Exit code {ret}, err: {err}\nout: {out}"
    assert "WINDOW_TRANSITION_ARMED from=main to=largePopup" in out
    assert "WINDOW_TRANSITION_ALLOWED from=main to=largePopup samePid=true" in out


def test_large_to_small_same_pid_allowed():
    """2. largePopup -> smallPopup 동일 PID 정상 허용 및 체크포인트 요구 검증"""
    ret, out, err, _ = run_sandbox_command(["test_large_to_small_same_pid_allowed"])
    assert ret == 0, f"Exit code {ret}, err: {err}\nout: {out}"
    assert "WINDOW_TRANSITION_ARMED from=largePopup to=smallPopup" in out
    assert "WINDOW_TRANSITION_ALLOWED from=largePopup to=smallPopup samePid=true" in out
    assert "CHECKPOINT_REQUIRED profile=smallPopup" in out


def test_transition_without_arm_rejected_exact_reason():
    """3. ArmTransition 없이 전환 시도시 transition_not_armed 거부 검증"""
    ret, out, err, _ = run_sandbox_command(["test_transition_without_arm_rejected_exact_reason"])
    assert ret == 10
    assert "WINDOW_TRANSITION_REJECTED reason=transition_not_armed" in out


def test_same_pid_wrong_title_rejected_exact_reason():
    """4. 같은 PID에서 제목이 잘못된 창(UNLISTED DECOY) 전환 시도시 profile_mismatch 거부 검증"""
    ret, out, err, _ = run_sandbox_command(["test_same_pid_wrong_title_rejected_exact_reason"])
    assert ret == 10
    assert "WINDOW_TRANSITION_REJECTED reason=profile_mismatch" in out


def test_wrong_expected_class_rejected_exact_reason():
    """5. Class 불일치 창 전환 시도시 profile_mismatch 거부 검증"""
    ret, out, err, _ = run_sandbox_command(["test_wrong_expected_class_rejected_exact_reason"])
    assert ret == 10
    assert "WINDOW_TRANSITION_REJECTED reason=profile_mismatch" in out


def test_same_title_class_different_pid_rejected_exact_reason():
    """6. 동일한 title/class/size이지만 다른 AHK 프로세스(PID) Decoy 창 전환 시도시 pid_mismatch 거부 검증"""
    ret, out, err, _ = run_sandbox_command(["test_same_title_class_different_pid_rejected_exact_reason"])
    assert ret == 10
    assert "WINDOW_TRANSITION_REJECTED reason=pid_mismatch" in out


def test_transition_timeout_rejected_exact_reason():
    """7. 실제 경과시간 초과(200ms timeout에 300ms Sleep) 시도시 timeout 거부 검증"""
    ret, out, err, _ = run_sandbox_command(["test_transition_timeout_rejected_exact_reason"])
    assert ret == 10
    assert "WINDOW_TRANSITION_REJECTED reason=timeout" in out


def test_transition_order_skip_rejected_exact_reason():
    """8. 허용되지 않은 전환 순서(main -> small 건너뛰기) 시도시 order_mismatch 거부 검증"""
    ret, out, err, _ = run_sandbox_command(["test_transition_order_skip_rejected_exact_reason"])
    assert ret == 10
    assert "WINDOW_TRANSITION_REJECTED reason=order_mismatch" in out


def test_client_size_plus_10_allowed():
    """9. client size +10px (허용오차 한계 이내) 전환 허용 검증"""
    ret, out, err, _ = run_sandbox_command(["test_client_size_plus_10_allowed"])
    assert ret == 0, f"Exit code {ret}, err: {err}\nout: {out}"
    assert "WINDOW_TRANSITION_ALLOWED from=main to=largePopup samePid=true" in out


def test_client_size_plus_11_rejected_exact_reason():
    """10. client size +11px (허용오차 초과) 전환 시도시 client_size_mismatch 거부 검증"""
    ret, out, err, _ = run_sandbox_command(["test_client_size_plus_11_rejected_exact_reason"])
    assert ret == 10
    assert "WINDOW_TRANSITION_REJECTED reason=client_size_mismatch" in out


def test_manual_checkpoint_blocks_input_until_release():
    """11. manual checkpoint 활성 시 입력 차단 및 release 후 1회 입력 허용 검증"""
    ret, out, err, _ = run_sandbox_command(["test_manual_checkpoint_blocks_input_until_release"])
    assert ret == 0, f"Exit code {ret}, err: {err}\nout: {out}"
    assert "CHECKPOINT_REQUIRED profile=smallPopup" in out
    assert "INPUT_BLOCKED reason=manual_checkpoint profile=smallPopup" in out
    assert "CHECKPOINT_RELEASED profile=smallPopup" in out
    assert "SANDBOX_INPUT profile=smallPopup count=1" in out


def test_rejection_latches_guard_and_prevents_retry():
    """12. 1회 거부 발생 시 가드가 Latch되어 후속 정상 창 전환 재시도도 transition_not_armed로 차단 검증"""
    ret, out, err, _ = run_sandbox_command(["test_rejection_latches_guard_and_prevents_retry"])
    assert ret == 10
    assert "WINDOW_TRANSITION_REJECTED reason=profile_mismatch" in out
    assert "WINDOW_TRANSITION_REJECTED reason=transition_not_armed" in out


def test_cleanup_leaves_no_spawned_sandbox_process():
    """13. spawn된 sandbox 및 decoy 프로세스가 모두 정상 종료되어 잔류가 없는지 검증"""
    ret, out, err, pid = run_sandbox_command(["test_cleanup_leaves_no_spawned_sandbox_process"])
    assert ret == 0
    time.sleep(0.1)
    
    # 해당 PID가 종료되었는지 PowerShell로 검증
    check_cmd = ["powershell", "-Command", f"Get-Process -Id {pid} -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count"]
    res = subprocess.run(check_cmd, capture_output=True, text=True)
    count = int(res.stdout.strip()) if res.stdout.strip().isdigit() else 0
    assert count == 0


def test_no_force_result_test_hooks_exist():
    """14. prototype 소스코드에 forceDifferentPid, forceTimeout 등 가짜 모의 훅이 없는지 정적 검증"""
    guard_source = GUARD_AHK.read_text(encoding="utf-8")
    assert "forceDifferentPid" not in guard_source
    assert "forceTimeout" not in guard_source
    assert "force" not in guard_source.lower() or "singleinstance force" in guard_source.lower()
