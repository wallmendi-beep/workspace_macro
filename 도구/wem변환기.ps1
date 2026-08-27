# ============================================================
# .wem -> 클립 초안 변환기 (v3.1 / schema v2)
# 용도: 기존 매크로 녹화 파일(.wem)을 읽어 본 프로젝트의
#       구간(Section)/클립(Clip) 초안 JSON과 사람용 검토 리포트(MD)를 생성한다.
# 사용법: powershell -File wem변환기.ps1 -WemPath "D:\xxx.wem"
# ============================================================
param(
    [Parameter(Mandatory=$true)][string]$WemPath,
    [string]$OutDir = (Join-Path $PSScriptRoot "..\변환 결과"),
    [string]$BaseResolution = "",  # 이전 호출 호환용. v2 유산 변환은 빈 값 또는 3840x1080만 허용
    [ValidateSet('auto','left','right')][string]$RecordedSegment = 'auto'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $WemPath)) { throw "파일을 찾을 수 없습니다: $WemPath" }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
if ($BaseResolution -ne '' -and $BaseResolution -notmatch '^3840\s*[xX×]\s*1080$') {
    throw "스키마 v2 유산 변환의 원본 범위는 3840x1080만 허용합니다: $BaseResolution"
}

$name = [System.IO.Path]::GetFileNameWithoutExtension($WemPath)
$raw  = [System.IO.File]::ReadAllText($WemPath)

# ---------- 키 코드 매핑 ----------
$usMap = @{}
for ($i=65; $i -le 90; $i++) { $usMap[$i] = [string][char]$i }
for ($i=48; $i -le 57; $i++) { $usMap[$i] = [string][char]$i }
@{8='Backspace';9='Tab';13='Enter';27='Esc';32='Space';186=';';187='=';188=',';189='-';190='.';191='/';192='`';219='[';220='\';221=']';222="'";}.GetEnumerator() | ForEach-Object { $usMap[$_.Key] = $_.Value }

# 두벌식 자판: 코드 -> 자모 (추정용)
$jamoMap = @{81='ㅂ';87='ㅈ';69='ㄷ';82='ㄱ';84='ㅅ';89='ㅛ';85='ㅕ';73='ㅑ';79='ㅐ';80='ㅔ';
             65='ㅁ';83='ㄴ';68='ㅇ';70='ㄹ';71='ㅎ';72='ㅗ';74='ㅓ';75='ㅏ';76='ㅣ';
             90='ㅋ';88='ㅌ';67='ㅊ';86='ㅍ';66='ㅠ';78='ㅜ';77='ㅡ'}

$vowelSet   = @('ㅏ','ㅐ','ㅑ','ㅒ','ㅓ','ㅔ','ㅕ','ㅖ','ㅗ','ㅛ','ㅜ','ㅠ','ㅡ','ㅣ')
$choList    = @('ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ')
$jungList   = @('ㅏ','ㅐ','ㅑ','ㅒ','ㅓ','ㅔ','ㅕ','ㅖ','ㅗ','ㅘ','ㅙ','ㅚ','ㅛ','ㅜ','ㅝ','ㅞ','ㅟ','ㅠ','ㅡ','ㅢ','ㅣ')
$jongList   = @('','ㄱ','ㄲ','ㄳ','ㄴ','ㄵ','ㄶ','ㄷ','ㄹ','ㄺ','ㄻ','ㄼ','ㄽ','ㄾ','ㄿ','ㅀ','ㅁ','ㅂ','ㅄ','ㅅ','ㅆ','ㅇ','ㅈ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ')
$vCompound  = @{ 'ㅗㅏ'='ㅘ'; 'ㅗㅐ'='ㅙ'; 'ㅗㅣ'='ㅚ'; 'ㅜㅓ'='ㅝ'; 'ㅜㅔ'='ㅞ'; 'ㅜㅣ'='ㅟ'; 'ㅡㅣ'='ㅢ' }
$jCompound  = @{ 'ㄱㅅ'='ㄳ'; 'ㄴㅈ'='ㄵ'; 'ㄴㅎ'='ㄶ'; 'ㄹㄱ'='ㄺ'; 'ㄹㅁ'='ㄻ'; 'ㄹㅂ'='ㄼ'; 'ㄹㅅ'='ㄽ'; 'ㄹㅌ'='ㄾ'; 'ㄹㅍ'='ㄿ'; 'ㄹㅎ'='ㅀ'; 'ㅂㅅ'='ㅄ' }

function Compose-Hangul([string]$jamos) {
    # IME 방식(보류 종성): 자음이 오면 일단 받침으로 붙여두고,
    # 다음에 모음이 오면 그 받침을 새 글자의 초성으로 넘긴다.
    $out = New-Object System.Text.StringBuilder
    $script:_cho = $null; $script:_jung = -1; $script:_jong = ''
    function Commit-Syl {
        if ($script:_cho -ne $null -and $script:_jung -ge 0) {
            $pre = if ($script:_jong.Length -gt 1) { $jCompound[$script:_jong] } else { $script:_jong }
            $code = 0xAC00 + (($choList.IndexOf($script:_cho) * 21 + $script:_jung) * 28) + [Math]::Max(0, $jongList.IndexOf($pre))
            [void]$out.Append([char]$code)
        } elseif ($script:_cho -ne $null) { [void]$out.Append($script:_cho) }
        $script:_cho = $null; $script:_jung = -1; $script:_jong = ''
    }
    foreach ($j in $jamos.ToCharArray()) {
        $j = [string]$j
        if ($vowelSet -contains $j) {
            if ($script:_cho -ne $null -and $script:_jung -lt 0) { $script:_jung = [array]::IndexOf($jungList, $j) }
            elseif ($script:_cho -ne $null -and $script:_jung -ge 0) {
                if ($script:_jong -ne '') {
                    # 보류 중이던 받침: 커밋에서는 받침을 빼고, 마지막 자음을 새 글자의 초성으로 승격
                    $newCho = if ($choList -contains ($script:_jong.Substring($script:_jong.Length-1))) { $script:_jong.Substring($script:_jong.Length-1) } else { 'ㅇ' }
                    if ($script:_jong.Length -gt 1) { $script:_jong = $script:_jong.Substring(0, $script:_jong.Length-1) } else { $script:_jong = '' }
                    Commit-Syl
                    $script:_cho = $newCho; $script:_jung = [array]::IndexOf($jungList, $j)
                } else {
                    $pair = "$($jungList[$script:_jung])$j"
                    if ($vCompound.ContainsKey($pair)) { $script:_jung = [array]::IndexOf($jungList, $vCompound[$pair]) }
                    else { Commit-Syl; $script:_cho = 'ㅇ'; $script:_jung = [array]::IndexOf($jungList, $j) }
                }
            }
            else { $script:_cho = 'ㅇ'; $script:_jung = [array]::IndexOf($jungList, $j) }
        }
        else { # 자음
            if ($script:_cho -ne $null -and $script:_jung -ge 0) {
                if ($script:_jong -eq '') { $script:_jong = $j }
                else {
                    $cand = "$($script:_jong)$j"
                    if ($jCompound.ContainsKey($cand)) { $script:_jong = $cand }  # 분해 상태로 보관 (예: 'ㄹㅅ')
                    else { Commit-Syl; $script:_cho = $j }
                }
            }
            elseif ($script:_cho -ne $null) { Commit-Syl; $script:_cho = $j }
            else { $script:_cho = $j }
        }
    }
    Commit-Syl
    return $out.ToString()
}

function Convert-KeyRun([int[]]$codes) {
    # 반환: @{ text=추정문자열; jamo=자모열; us=영문배열추정; notes=@() }
    $sbHangul = New-Object System.Text.StringBuilder
    $sbJamo   = New-Object System.Text.StringBuilder
    $sbUs     = New-Object System.Text.StringBuilder
    $notes    = New-Object System.Collections.ArrayList
    foreach ($c in $codes) {
        if ($c -eq 13)      { [void]$sbHangul.Append("`n"); [void]$sbJamo.Append("`n"); [void]$sbUs.Append("`n") }
        elseif ($c -eq 32)  { [void]$sbHangul.Append(' '); [void]$sbJamo.Append(' '); [void]$sbUs.Append(' ') }
        elseif ($c -eq 8)   { [void]$notes.Add('Backspace 포함(삭제 동작)') ; [void]$sbHangul.Append('[BS]'); [void]$sbJamo.Append('[BS]'); [void]$sbUs.Append('[BS]') }
        elseif ($usMap.ContainsKey($c)) {
            $u = $usMap[$c]
            [void]$sbUs.Append($u)
            if ($jamoMap.ContainsKey($c)) { $jm = $jamoMap[$c]; [void]$sbJamo.Append($jm); [void]$sbHangul.Append($jm) }
            else { [void]$sbHangul.Append($u); [void]$sbJamo.Append($u) }
        }
        else { [void]$notes.Add("미확인 코드 $c") }
    }
    $composed = Compose-Hangul $sbJamo.ToString()
    return @{ text=$composed; jamo=$sbJamo.ToString(); us=$sbUs.ToString(); notes=$notes }
}

# ---------- 1단계: 토큰 파싱 ----------
$tokens = $raw -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }

$events     = New-Object System.Collections.ArrayList   # @{ kind='click'|'keys'; ... }
$keyBuf     = New-Object System.Collections.ArrayList
$lastX = 0; $lastY = 0
$downX = $null; $downY = $null
$movesSinceAction = 0

function Emit-TextEvent([System.Collections.ArrayList]$list) {
    $codes = [int[]]$list.ToArray()
    $r = Convert-KeyRun $codes
    [void]$script:events.Add(@{ kind='keys'; codes=$codes; before=$script:movesSinceAction; result=$r })
}

function Flush-KeyRun {
    # Enter(13)·Tab(9)은 텍스트에 섞지 않고 독립된 기능키 클립으로 분리 (재생 안전성)
    if ($script:keyBuf.Count -eq 0) { return }
    $seg = New-Object System.Collections.ArrayList
    foreach ($c in [int[]]$script:keyBuf.ToArray()) {
        if ($c -eq 13 -or $c -eq 9) {
            if ($seg.Count -gt 0) { Emit-TextEvent $seg; $seg.Clear() }
            $keyName = if ($c -eq 13) { 'ENTER' } else { 'TAB' }
            [void]$script:events.Add(@{ kind='key'; key=$keyName; before=$script:movesSinceAction })
        } else { [void]$seg.Add($c) }
    }
    if ($seg.Count -gt 0) { Emit-TextEvent $seg }
    $script:keyBuf.Clear()
    $script:movesSinceAction = 0
}

$totalSamples = 0
$maxX = 0; $maxY = 0
$clickMaxX = 0; $clickMaxY = 0
foreach ($tok in $tokens) {
    if ($tok -match '^\[(\d+),(\d+)\]$') {
        $lastX = [int]$Matches[1]; $lastY = [int]$Matches[2]
        if ($lastX -gt $maxX) { $maxX = $lastX }
        if ($lastY -gt $maxY) { $maxY = $lastY }
        $totalSamples++; $movesSinceAction++
    }
    elseif ($tok -eq 'Down') { $downX = $lastX; $downY = $lastY }
    elseif ($tok -eq 'Up') {
        Flush-KeyRun
        if ($downX -ne $null) {
            [void]$events.Add(@{ kind='click'; x=$downX; y=$downY; before=$movesSinceAction })
            if ($downX -gt $clickMaxX) { $clickMaxX = $downX }
            if ($downY -gt $clickMaxY) { $clickMaxY = $downY }
            $downX = $null; $downY = $null; $movesSinceAction = 0
        }
    }
    elseif ($tok -match '^\((\d+)\)$') { [void]$keyBuf.Add([int]$Matches[1]) }
    elseif ($tok -match '^<(\d+)>$') { }
}

Flush-KeyRun

# ---------- 1-1. 원본 모니터 판정 및 좌표 안전검증 ----------
$MONITOR_W = 1920
$MONITOR_H = 1080
$clickEvents = @($events | Where-Object { $_.kind -eq 'click' })
if ($clickEvents.Count -eq 0) {
    if ($RecordedSegment -eq 'auto') { throw "클릭 좌표가 없어 원본 모니터를 자동 판정할 수 없습니다. -RecordedSegment left 또는 right를 지정하세요." }
    $segment = $RecordedSegment
} else {
    foreach ($ev in $clickEvents) {
        if ($ev.x -lt 0 -or $ev.x -ge ($MONITOR_W * 2) -or $ev.y -lt 0 -or $ev.y -ge $MONITOR_H) {
            throw "듀얼 FHD 원본 범위를 벗어난 클릭 좌표입니다: ($($ev.x), $($ev.y))"
        }
    }
    $hasLeft  = @($clickEvents | Where-Object { $_.x -lt $MONITOR_W }).Count -gt 0
    $hasRight = @($clickEvents | Where-Object { $_.x -ge $MONITOR_W }).Count -gt 0
    if ($hasLeft -and $hasRight) {
        throw "한 매크로에 여러 모니터의 클릭 좌표가 섞여 있어 안전하게 정규화할 수 없습니다."
    }
    $detectedSegment = if ($hasRight) { 'right' } else { 'left' }
    if ($RecordedSegment -ne 'auto' -and $RecordedSegment -ne $detectedSegment) {
        throw "지정한 원본 모니터($RecordedSegment)와 클릭 좌표 판정($detectedSegment)이 일치하지 않습니다."
    }
    $segment = $detectedSegment
}

# ---------- 2단계: 구간 분할 (이동 많은 지점에서 구간 경계 제안) ----------
$SECTION_THRESHOLD = 25
$sections = New-Object System.Collections.ArrayList
$cur = @{ id = "sec_1"; label = "구간 1"; clips = (New-Object System.Collections.ArrayList) }
[void]$sections.Add($cur)
foreach ($ev in $events) {
    if ($ev.before -ge $SECTION_THRESHOLD -and $cur.clips.Count -gt 0) {
        $cur = @{ id = "sec_" + ($sections.Count + 1); label = "구간 $($sections.Count + 1) (자동분할)"; clips = (New-Object System.Collections.ArrayList) }
        [void]$sections.Add($cur)
    }
    if ($ev.kind -eq 'click') {
        $normX = if ($segment -eq 'right') { $ev.x - $MONITOR_W } else { $ev.x }
        if ($normX -lt 0 -or $normX -ge $MONITOR_W -or $ev.y -lt 0 -or $ev.y -ge $MONITOR_H) {
            throw "정규화 좌표가 단일 FHD 모니터 범위를 벗어났습니다: ($normX, $($ev.y))"
        }
        [void]$cur.clips.Add(@{ type='mouse'; action='left_click'; x=$normX; y=$ev.y; coordMode='screen'; note=''; interval='' })
    } elseif ($ev.kind -eq 'key') {
        [void]$cur.clips.Add(@{ type='key'; key=$ev.key; note='내비게이션 키'; interval='' })
    } else {
        $r = $ev.result
        [void]$cur.clips.Add(@{ type='text'; input_method='typing'; value=$r.text; jamo_guess=$r.jamo; us_guess=$r.us;
                                notes=($r.notes -join '; '); note=''; interval='' })
    }
}

# ---------- 2-1. 연속 클릭(더블클릭 의심) 주석 ----------
# 자동 병합은 하지 않는다: 같은 버튼 확인용 2연타일 수 있어 동작 변경 위험. 검토 대상으로만 표시.
$prevClick = $null
foreach ($sec in $sections) {
    foreach ($c in $sec.clips) {
        if ($c.type -eq 'mouse') {
            if ($prevClick -ne $null -and $prevClick.x -eq $c.x -and $prevClick.y -eq $c.y) {
                $c.note = '연속 클릭 - 더블클릭 의심 (검토 필요)'
            }
            $prevClick = $c
        } elseif ($c.type -ne 'key') { $prevClick = $null }
    }
}

# ---------- 3단계: JSON 생성 ----------
$jsonObj = [ordered]@{
    format          = 'regimacro'
    version         = 2
    name            = $name
    createdAt       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    source          = [ordered]@{
        type                    = 'wem-import'
        file                    = (Split-Path $WemPath -Leaf)
        recordedSegment         = $segment
        originalSpan            = 'dual-fhd-3840x1080'
        coordinateNormalization = 'monitor-local'
    }
    baseResolution  = [ordered]@{ width = $MONITOR_W; height = $MONITOR_H }
    settings        = @{ defaultIntervalMs = 2000 }
    sections        = $sections
}
$jsonObj['importStats'] = @{
    totalSamples   = $totalSamples
    clickCount     = @($events | Where-Object { $_.kind -eq 'click' }).Count
    keyRunCount    = (@($events | Where-Object { $_.kind -eq 'keys' }).Count + @($events | Where-Object { $_.kind -eq 'key' }).Count)
    sectionCount   = $sections.Count
}
$json = $jsonObj | ConvertTo-Json -Depth 6
$jsonPath = Join-Path $OutDir "${name}_초안.json"
[System.IO.File]::WriteAllText($jsonPath, $json, (New-Object System.Text.UTF8Encoding($false)))

# ---------- 4단계: 사람용 리포트(MD) ----------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# ${name} — 변환 초안 리포트")
[void]$sb.AppendLine()
[void]$sb.AppendLine("- 원본: ``$(Split-Path $WemPath -Leaf)``")
[void]$sb.AppendLine("- 스키마: v2 / 원본 모니터: $segment")
[void]$sb.AppendLine("- 좌표: 듀얼 FHD 원본을 단일 FHD 1920×1080 내부좌표로 정규화")
[void]$sb.AppendLine("- 샘플 수: $totalSamples / 클릭: $(@($events | Where-Object { $_.kind -eq 'click' }).Count)건 / 키 입력 묶음: $(@($events | Where-Object { $_.kind -eq 'keys' }).Count)건 / 구간(자동): $($sections.Count)")
[void]$sb.AppendLine()
[void]$sb.AppendLine("> 자동 분할된 구간·추정 문자는 **초안**입니다. 등기 시스템 화면과 대조해 레이블·주석을 붙여 주세요.")
[void]$sb.AppendLine()
$secNo = 0
foreach ($sec in $sections) {
    $secNo++
    [void]$sb.AppendLine("## $($sec.label)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("| 순번 | 클립 | 내용 | 좌표/비고 |")
    [void]$sb.AppendLine("| --- | --- | --- | --- |")
    $clipNo = 0
    foreach ($c in $sec.clips) {
        $clipNo++
        if ($c.type -eq 'mouse') {
            $coordNote = "$($c.x), $($c.y)"
            if ($c.note) { $coordNote += " / $($c.note)" }
            [void]$sb.AppendLine("| $clipNo | 마우스 클릭 | (좌클릭) | $coordNote |")
        } elseif ($c.type -eq 'key') {
            [void]$sb.AppendLine("| $clipNo | 기능키 | ``$($c.key)`` | 내비게이션 키 |")
        } else {
            $val = ($c.value -replace "`n", " ⏎ ")
            $note = $c.notes
            if (-not $note) { $note = "-" }
            [void]$sb.AppendLine("| $clipNo | 텍스트 입력 | ``$val`` | 추정: $($c.us_guess) / $note |")
        }
    }
    [void]$sb.AppendLine()
}
$mdPath = Join-Path $OutDir "${name}_초안.md"
[System.IO.File]::WriteAllText($mdPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Output ("완료: " + $jsonPath)
Write-Output ("완료: " + $mdPath)
