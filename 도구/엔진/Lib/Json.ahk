; ============================================================
; RegiMacro — 경량 JSON 파서 (Lib\Json.ahk)
; 본 프로젝트 변환기(wem변환기.ps1)가 만드는 JSON을 읽기 위한
; 자체 파서. 외부 라이브러리 없이 동작.
; 반환: 객체 → Map, 배열 → Array, 숫자 → Number, 문자열 → String
; ============================================================
#Requires AutoHotkey v2.0

class JsonParser {
    __New(str) {
        this.s := str
        this.pos := 1
        this.len := StrLen(str)
    }

    static Load(str) {
        p := JsonParser(str)
        p.SkipWs()
        v := p.Value()
        return v
    }

    SkipWs() {
        while (this.pos <= this.len) {
            ch := SubStr(this.s, this.pos, 1)
            if (ch = " " || ch = "`t" || ch = "`r" || ch = "`n")
                this.pos++
            else
                break
        }
    }

    Expect(ch) {
        this.SkipWs()
        if (SubStr(this.s, this.pos, 1) != ch)
            throw Error("JSON 오류: '" ch "' 예상 위치 — offset " this.pos)
        this.pos++
    }

    Value() {
        this.SkipWs()
        ch := SubStr(this.s, this.pos, 1)
        if (ch = "{")
            return this.Obj()
        if (ch = "[")
            return this.Arr()
        if (ch = "`"")
            return this.Str()
        if (SubStr(this.s, this.pos, 4) = "true")
            return ((this.pos += 4), true)
        if (SubStr(this.s, this.pos, 5) = "false")
            return ((this.pos += 5), false)
        if (SubStr(this.s, this.pos, 4) = "null")
            return ((this.pos += 4), "")
        return this.Num()
    }

    Lit(word, val) {
        if (SubStr(this.s, this.pos, StrLen(word)) != word)
            throw Error("JSON 오류: " word)
        this.pos += StrLen(word)
        return val
    }

    Num() {
        start := this.pos
        while (this.pos <= this.len) {
            ch := SubStr(this.s, this.pos, 1)
            if (ch ~= "[0-9eE\+\-\.]")
                this.pos++
            else
                break
        }
        numStr := SubStr(this.s, start, this.pos - start)
        if (numStr = "")
            throw Error("JSON 오류: 숫자 예상 위치 — offset " start)
        return numStr + 0
    }

    Str() {
        ; 현재 위치는 여는 따옴표
        this.pos++
        out := ""
        while (this.pos <= this.len) {
            ch := SubStr(this.s, this.pos, 1)
            if (ch = "`"") {
                this.pos++
                return out
            } else if (ch = "\") {
                this.pos++
                e := SubStr(this.s, this.pos, 1)
                if (e = "`"")
                    out .= "`"", this.pos++
                else if (e = "\")
                    out .= "\", this.pos++
                else if (e = "/")
                    out .= "/", this.pos++
                else if (e = "n")
                    out .= "`n", this.pos++
                else if (e = "t")
                    out .= A_Tab, this.pos++
                else if (e = "r")
                    this.pos++
                else if (e = "b" || e = "f")
                    this.pos++
                else if (e = "u") {
                    hex := SubStr(this.s, this.pos + 1, 4)
                    code := Integer("0x" hex)
                    this.pos += 5
                    ; 서러게이트 쌍 처리
                    if (code >= 0xD800 && code <= 0xDBFF && SubStr(this.s, this.pos, 2) = "\u") {
                        loHex := SubStr(this.s, this.pos + 2, 4)
                        lo := Integer("0x" loHex)
                        if (lo >= 0xDC00 && lo <= 0xDFFF) {
                            code := 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00)
                            this.pos += 6
                        }
                    }
                    out .= Chr(code)
                } else
                    out .= e, this.pos++
            } else {
                out .= ch
                this.pos++
            }
        }
        throw Error("JSON 오류: 문자열 종료 따옴표 없음")
    }

    Obj() {
        m := Map()
        this.Expect("{")
        this.SkipWs()
        if (SubStr(this.s, this.pos, 1) = "}") {
            this.pos++
            return m
        }
        loop {
            this.SkipWs()
            key := this.Str()
            this.Expect(":")
            m[key] := this.Value()
            this.SkipWs()
            ch := SubStr(this.s, this.pos, 1)
            if (ch = ",") {
                this.pos++
                continue
            }
            if (ch = "}") {
                this.pos++
                return m
            }
            throw Error("JSON 오류: 개체 구분자 이상 — offset " this.pos)
        }
    }

    Arr() {
        a := Array()
        this.Expect("[")
        this.SkipWs()
        if (SubStr(this.s, this.pos, 1) = "]") {
            this.pos++
            return a
        }
        loop {
            a.Push(this.Value())
            this.SkipWs()
            ch := SubStr(this.s, this.pos, 1)
            if (ch = ",") {
                this.pos++
                continue
            }
            if (ch = "]") {
                this.pos++
                return a
            }
            throw Error("JSON 오류: 배열 구분자 이상 — offset " this.pos)
        }
    }
}
