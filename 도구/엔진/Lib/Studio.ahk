; ============================================================
; RegiMacro — 스튜디오 UI (Lib\Studio.ahk)
; 디자인 레퍼런스(사용자 제공 목업 2종)를 참고한 다크 테마 3분할:
;   좌측 구간 목록 | 중앙 클립 타임라인(테이블) | 우측 클립 속성
; 상단 트랜스포트 바 + 하단 진행률. 재생 중 현재 클립이 강조된다.
; (풀 타임라인 뷰 — 드래그 편집 — 는 차기 버전 과제)
; ============================================================
#Requires AutoHotkey v2.0

class Studio {
    __New(player, title) {
        this.player := player
        this.lastHL := 0
        this.title := title

        g := Gui("+AlwaysOnTop", "RegiMacro Studio")
        this.gui := g
        g.BackColor := "1B1B27"
        g.MarginX := 12
        g.MarginY := 10
        g.SetFont("s9 cE8E8F0", "Segoe UI")

        ; ── 헤더: 제목 + 모드 배지
        g.SetFont("s11 Bold")
        g.Add("Text", "w700 h26 c9FE870 BackgroundTrans", title)
        g.SetFont("s9 Norm")
        this.tMode := g.Add("Text", "x+16 yp w160 h26 cFFD24A BackgroundTrans Right", "")

        ; ── 트랜스포트 바
        bHome  := g.Add("Button", "xm y+10 w86 h32", "⏮ 처음")
        bPrev  := g.Add("Button", "x+6 w104 h32", "◀ 이전 구간")
        bPlay  := g.Add("Button", "x+6 w116 h32", "▶ 시작 / 재개")
        bPause := g.Add("Button", "x+6 w96 h32", "⏸ 일시정지")
        bNext  := g.Add("Button", "x+6 w104 h32", "▶| 다음 구간")
        bStop  := g.Add("Button", "x+6 w80 h32", "⏹ 정지")
        this.tPos := g.Add("Text", "x+18 yp+6 w170 h26 cFFFFFF BackgroundTrans Right", "클립 0 / 0")
        bHome.OnEvent("Click", (*) => this.player.GoHome())
        bPrev.OnEvent("Click", (*) => this.player.PrevSection())
        bPlay.OnEvent("Click", (*) => this.player.StartOrResume())
        bPause.OnEvent("Click", (*) => this.player.Pause())
        bNext.OnEvent("Click", (*) => this.player.NextSection())
        bStop.OnEvent("Click", (*) => this.player.GoEndStop())

        ; ── 좌측: 구간 목록
        g.Add("Text", "xm y+14 w210 h20 c9AA0B5 BackgroundTrans", "구간 (더블클릭 = 이동)")
        secNames := []
        for sIdx, sec in player.macro["sections"]
            secNames.Push(sIdx ". " player.Label(sIdx))
        this.lbSec := g.Add("ListBox", "xm y+4 w210 h430 Background23233A cE8E8F0", secNames)
        this.lbSec.OnEvent("DoubleClick", (ctrl) => this.player.JumpToSection(ctrl.Value))

        ; ── 중앙: 클립 타임라인 테이블
        g.Add("Text", "x+14 yp w560 h20 c9AA0B5 BackgroundTrans", "클립 타임라인 (재생 중 현재 단계 강조)")
        this.lv := g.Add("ListView", "x+0 y+4 w560 h430 Background23233A cE8E8F0 -Hdr", ["#", "구간", "종류", "내용", "위치/키", "간격", "주석"])
        this.lv.OnEvent("Click", (ctrl) => this.ShowInspector(ctrl.GetNext(0)))
        this.PopulateClips()
        this.lv.ModifyCol(1, 44), this.lv.ModifyCol(2, 44), this.lv.ModifyCol(3, 64)
        this.lv.ModifyCol(4, 210), this.lv.ModifyCol(5, 90), this.lv.ModifyCol(6, 48), this.lv.ModifyCol(7, 60)

        ; ── 우측: 클립 속성 인스펙터
        g.Add("Text", "x+14 yp w250 h20 c9AA0B5 BackgroundTrans", "클립 속성")
        g.Add("Text", "x+0 y+4 w250 h20 c68708A BackgroundTrans", "종류")
        this.iKind := g.Add("Text", "x+0 y+2 w250 h20 cFFFFFF BackgroundTrans", "-")
        g.Add("Text", "x+0 y+10 w250 h20 c68708A BackgroundTrans", "내용")
        this.iValue := g.Add("Text", "x+0 y+2 w250 h40 cFFFFFF BackgroundTrans", "-")
        g.Add("Text", "x+0 y+10 w250 h20 c68708A BackgroundTrans", "위치 / 키")
        this.iPos := g.Add("Text", "x+0 y+2 w250 h20 cFFFFFF BackgroundTrans", "-")
        g.Add("Text", "x+0 y+10 w250 h20 c68708A BackgroundTrans", "입력 방식")
        this.iMethod := g.Add("Text", "x+0 y+2 w250 h20 cFFFFFF BackgroundTrans", "-")
        g.Add("Text", "x+0 y+10 w250 h20 c68708A BackgroundTrans", "간격 (클립별)")
        this.iInterval := g.Add("Text", "x+0 y+2 w250 h20 cFFFFFF BackgroundTrans", "기본값")
        g.Add("Text", "x+0 y+10 w250 h20 c68708A BackgroundTrans", "주석")
        this.iNote := g.Add("Text", "x+0 y+2 w250 h60 cFFD24A BackgroundTrans", "-")

        ; ── 하단: 진행 바 + 상태
        this.bar := g.Add("Progress", "xm y+14 w1060 h12 c3B82F6 Background2A2A40 Range0-100", 0)
        this.tStatus := g.Add("Text", "xm y+6 w1060 h20 c9AA0B5 BackgroundTrans", "대기 — 트리거 키 또는 ▶ 버튼으로 시작")

        g.OnEvent("Close", (*) => ExitApp())
        g.Show()
        this.Update()
    }

    PopulateClips() {
        p := this.player
        for i, step in p.steps {
            c := p.GetClip(step)
            t := String(c["type"])
            if (t = "mouse") {
                kind := "마우스"
                detail := c["x"] ", " c["y"]
            } else if (t = "key") {
                kind := "기능키"
                detail := String(c["key"])
            } else {
                kind := "텍스트"
                detail := Trim(StrReplace(String(c.Has("value") ? c["value"] : ""), "`n", " "))
                if (StrLen(detail) > 40)
                    detail := SubStr(detail, 1, 40) "…"
            }
            note := c.Has("note") ? String(c["note"]) : ""
            iv := c.Has("interval") && c["interval"] != "" ? String(c["interval"]) : ""
            posKey := (t = "mouse" || t = "key") ? detail : ""
            this.lv.Add("", i, step.s, kind, detail, posKey, iv, note)
        }
    }

    ShowInspector(row) {
        p := this.player
        if (row < 1 || row > p.TotalSteps()) {
            this.iKind.Text := "-", this.iValue.Text := "-"
            this.iPos.Text := "-", this.iMethod.Text := "-"
            this.iInterval.Text := "기본값", this.iNote.Text := "-"
            return
        }
        c := p.GetClip(p.steps[row])
        t := String(c["type"])
        if (t = "mouse") {
            this.iKind.Text := "마우스 클릭"
            this.iValue.Text := "(좌클릭)"
            this.iPos.Text := c["x"] ", " c["y"]
            this.iMethod.Text := "-"
        } else if (t = "key") {
            this.iKind.Text := "기능키"
            this.iValue.Text := String(c["key"])
            this.iPos.Text := String(c["key"])
            this.iMethod.Text := "-"
        } else {
            this.iKind.Text := "텍스트 입력"
            v := String(c.Has("value") ? c["value"] : "")
            this.iValue.Text := StrLen(v) > 80 ? SubStr(v, 1, 80) "…" : v
            this.iPos.Text := "-"
            m := c.Has("input_method") ? String(c["input_method"]) : "typing"
            this.iMethod.Text := (InStr(m, "typing") = 1) ? "타이핑" : "붙여넣기 (Ctrl+V)"
        }
        this.iInterval.Text := (c.Has("interval") && c["interval"] != "") ? String(c["interval"]) " ms" : "기본값"
        this.iNote.Text := c.Has("note") && c["note"] != "" ? String(c["note"]) : "-"
    }

    ToggleVisible() {
        if (this.gui.Visible)
            this.gui.Hide()
        else
            this.gui.Show()
    }

    Update() {
        p := this.player
        n := p.TotalSteps()
        cur := p.CurrentStep()

        ; 모드 배지
        this.tMode.Text := p.dryRun ? "● 모의 모드" : "● 실제 입력"
        this.tMode.Opt(p.dryRun ? "c7CFC00" : "cFF5A5A")

        ; 상태 줄
        if (p.state = Player.RUNNING)
            this.tStatus.Text := "실행 중 — 현재: " p.ClipSummary(p.steps[cur])
        else if (p.state = Player.PAUSED)
            this.tStatus.Text := "일시정지 — 재개하려면 트리거 키 / Scroll Lock"
        else
            this.tStatus.Text := "대기 — 트리거 키 또는 ▶ 버튼으로 시작"

        ; 위치 · 진행률
        this.tPos.Text := "클립 " (cur >= 1 ? cur : 0) " / " n
        this.bar.Value := (n > 0 && cur >= 1) ? Round((cur - 1) / n * 100) : 0

        ; 현재 클립 강조 (변경 시에만)
        if (cur >= 1 && cur <= n && cur != this.lastHL) {
            if (this.lastHL >= 1)
                this.lv.Modify(this.lastHL, "-Select")
            this.lv.Modify(cur, "+Select Vis")
            this.lastHL := cur
            this.ShowInspector(cur)
        } else if (cur = 0 && this.lastHL >= 1) {
            this.lv.Modify(this.lastHL, "-Select")
            this.lastHL := 0
        }
    }
}
