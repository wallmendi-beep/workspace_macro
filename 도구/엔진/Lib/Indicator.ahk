; ============================================================
; RegiMacro — 초경량 플로팅 오버레이 HUD (Lib\Indicator.ahk)
; 등기 시스템 화면 위에 최상위(+AlwaysOnTop)로 떠서
; 작업표시줄을 회피(WorkingArea 기준 우측 하단 자동 배치)하며,
; 실시간 진행률(유튜브 시크바), 현재 구간/클립, 미니 컨트롤을 제공합니다.
; ============================================================
#Requires AutoHotkey v2.0

class OverlayIndicator {
    __New(player, title := "RegiMacro HUD") {
        this.player := player
        this.title := title
        this.isVisible := true

        ; 다크 테마 플로팅 HUD 창 생성
        g := Gui("+AlwaysOnTop -DPIScale +ToolWindow -Caption +Border", "RegiMacro Overlay HUD")
        this.gui := g
        g.BackColor := "12121E"
        g.MarginX := 8
        g.MarginY := 6
        g.SetFont("s9 cE8E8F0", "Segoe UI")

        ; ── 상단 헤더: 드래그 이동 핸들 + 타이틀 + 상태 배지
        this.tTitle := g.Add("Text", "w190 h20 c9FE870 BackgroundTrans Bold", title)
        this.tStatus := g.Add("Text", "x+10 yp w110 h20 cFFD24A BackgroundTrans Right Bold", "대기")

        ; ── 중앙: 유튜브 시크바 진행률 + 클립 요약
        this.bar := g.Add("Progress", "xm y+4 w310 h8 c3B82F6 Background2A2A40 Range0-100", 0)
        this.tClip := g.Add("Text", "xm y+4 w310 h18 cFFFFFF BackgroundTrans Center", "준비 완료")

        ; ── 하단: 미니 트랜스포트 컨트롤 바
        bHome  := g.Add("Button", "xm y+4 w42 h24", "⏮")
        bPrev  := g.Add("Button", "x+3 w44 h24", "◀")
        bPlay  := g.Add("Button", "x+3 w56 h24 Bold", "▶/⏸")
        bNext  := g.Add("Button", "x+3 w44 h24", "▶|")
        bStop  := g.Add("Button", "x+3 w42 h24", "⏹")
        bHide  := g.Add("Button", "x+6 w56 h24", "최소화")

        bHome.OnEvent("Click", (*) => this.player.GoHome())
        bPrev.OnEvent("Click", (*) => this.player.PrevSection())
        bPlay.OnEvent("Click", (*) => this.player.StartOrResume())
        bNext.OnEvent("Click", (*) => this.player.NextSection())
        bStop.OnEvent("Click", (*) => this.player.GoEndStop())
        bHide.OnEvent("Click", (*) => this.ToggleVisible())

        ; 창 드래그 이동 지원 (클릭 후 드래그 시 이동)
        this.tTitle.OnEvent("Click", (*) => this.DragWindow())
        this.tClip.OnEvent("Click", (*) => this.DragWindow())

        ; 대상 모니터 WorkingArea 기준 우측 하단 자동 배치
        this.AutoPosition()
        g.Show("NoActivate")
        this.Update()
    }

    AutoPosition() {
        mon := this.player.targetMon
        if (mon < 1 || mon > MonitorGetCount())
            mon := 1
        
        MonitorGetWorkArea(mon, &wl, &wt, &wr, &wb)
        w := 326
        h := 96
        x := wr - w - 16
        y := wb - h - 16
        this.gui.Move(x, y, w, h)
    }

    DragWindow() {
        PostMessage 0xA1, 2, 0,, this.gui.Hwnd
    }

    ToggleVisible() {
        if (this.isVisible) {
            this.gui.Hide()
            this.isVisible := false
        } else {
            this.gui.Show("NoActivate")
            this.isVisible := true
            this.Update()
        }
    }

    Update() {
        if (!this.isVisible)
            return

        p := this.player
        tot := p.TotalSteps()
        cur := p.CurrentStep()

        ; 진행률 계산
        pct := (tot > 0 && cur > 0) ? Integer((cur / tot) * 100) : 0
        this.bar.Value := pct

        ; 상태 텍스트
        st := p.state
        if (st = Player.RUNNING)
            this.tStatus.Text := "실행중 " cur "/" tot
        else if (st = Player.PAUSED)
            this.tStatus.Text := "일시정지 " cur "/" tot
        else
            this.tStatus.Text := "대기 (" tot "스텝)"

        ; 현재 클립 정보
        if (cur >= 1 && cur <= tot) {
            step := p.steps[cur]
            summary := p.ClipSummary(step)
            secLabel := p.Label(step.s)
            this.tClip.Text := secLabel " ❯ " summary
        } else {
            this.tClip.Text := "트리거(^!r) 또는 ▶ 로 시작"
        }
    }
}
