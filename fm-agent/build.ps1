# matches\*.json 을 검증한 뒤 dashboard.html 안에 데이터를 심는다.
# 사용법:  powershell -ExecutionPolicy Bypass -File build.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$matchDir = Join-Path $root 'matches'
$dashboard = Join-Path $root 'dashboard.html'

# --- 표준 팀명 목록 -------------------------------------------------------
$known = @{}
$teamsFile = Join-Path $root 'teams.json'
if (Test-Path $teamsFile) {
    $t = (Get-Content $teamsFile -Raw -Encoding UTF8 | ConvertFrom-Json).teams
    foreach ($p in $t.PSObject.Properties) {
        $known[$p.Name] = $true
        foreach ($alias in $p.Value) { $known[$alias] = $p.Name }
    }
}

# --- 표준 대회명 목록 -----------------------------------------------------
$comps = @{}
$compFile = Join-Path $root 'competitions.json'
if (Test-Path $compFile) {
    $c = (Get-Content $compFile -Raw -Encoding UTF8 | ConvertFrom-Json).competitions
    foreach ($p in $c.PSObject.Properties) {
        $comps[$p.Name] = $true
        foreach ($alias in $p.Value) { $comps[$alias] = $p.Name }
    }
}

# --- 스쿼드 명단 (선수명 대조용) ------------------------------------------
# 잘린 이름·오타는 player-aliases.json 으로는 못 잡는다. 실제 명단과 대조해야 한다.
$rosterNames = @{}
$csvWarnings = @()
$csvAttributes = $null
$csvPlayerNames = @()
$csvFile = Join-Path $root 'squad\선수_능력치_기록표.csv'
if (Test-Path $csvFile) {
    try {
        # Excel에서 저장한 CSV는 환경에 따라 CP949 또는 UTF-8이다. 둘 다 읽는다.
        $bytes = [System.IO.File]::ReadAllBytes($csvFile)
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        try { $csvText = $strictUtf8.GetString($bytes) } catch { $csvText = $null }
        if (-not $csvText -or $csvText.IndexOf([char]0xFFFD) -ge 0) {
            $csvText = [System.Text.Encoding]::GetEncoding(949).GetString($bytes)
        }
        $csvRows = @(ConvertFrom-Csv -InputObject $csvText)
        $groups = [ordered]@{
            '기술' = @('개인기','골결','드리블','일대일','중거리','크로스','태클','패스','퍼스트터치','헤더')
            '정신' = @('대담','리더십','수비위치','승부욕','시야','예측','오프더볼','적극','집중','천재','침착','팀워크','판단','활동량')
            '신체' = @('가속','균형','몸싸움','민첩','점프','주력','지구력','체력')
        }
        $csvPlayers = [ordered]@{}
        foreach ($row in $csvRows) {
            $name = [string]$row.PSObject.Properties['이름'].Value
            if (-not $name) { continue }
            $name = $name.Trim()
            $csvPlayerNames += $name
            $out = [ordered]@{}

            $posRaw = [string]$row.PSObject.Properties['포지션'].Value
            if ($posRaw -and $posRaw -ne '-') {
                $positions = @()
                foreach ($code in ($posRaw -split '[,\s]+' | Where-Object { $_ })) {
                    switch ($code.Trim().ToUpperInvariant()) {
                        'AMLR' { $positions += 'AML'; $positions += 'AMR' }
                        'DLR'  { $positions += 'DL';  $positions += 'DR' }
                        default { $positions += $code.Trim().ToUpperInvariant() }
                    }
                }
                $out['포지션'] = @($positions | Select-Object -Unique)
            }
            $left = [string]$row.PSObject.Properties['왼발'].Value
            $right = [string]$row.PSObject.Properties['오른발'].Value
            if (($left -and $left -ne '-') -or ($right -and $right -ne '-')) {
                $out['발'] = [ordered]@{ 왼발 = $left; 오른발 = $right }
            }
            $traitsRaw = [string]$row.PSObject.Properties['특성'].Value
            if ($traitsRaw -and $traitsRaw -ne '-' -and $traitsRaw -ne 'X') {
                $out['특성'] = @($traitsRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            } else { $out['특성'] = @() }

            foreach ($groupName in $groups.Keys) {
                $stats = [ordered]@{}
                foreach ($label in $groups[$groupName]) {
                    $prop = $row.PSObject.Properties[$label]
                    if ($null -eq $prop -or $null -eq $prop.Value -or [string]$prop.Value -eq '') { continue }
                    $num = 0
                    if ([int]::TryParse(([string]$prop.Value).Trim(), [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
                        $stats[$label] = $num
                    } else { $csvWarnings += "[$name] $groupName·$label 값을 숫자로 읽지 못했습니다: $($prop.Value)" }
                }
                $out[$groupName] = $stats
            }
            if ($out['포지션'] -contains 'GK') { $out['골키퍼'] = $true }
            $csvPlayers[$name] = $out
        }
        $csvAttributes = [ordered]@{
            updated = (Get-Date -Format 'yyyy-MM-dd')
            source_file = 'squad/선수_능력치_기록표.csv'
            note = '감독이 직접 입력한 CSV. 빈 칸은 기록 없음으로 처리한다.'
            players = $csvPlayers
        }
    } catch { $csvWarnings += "[CSV 오류] squad\선수_능력치_기록표.csv — $($_.Exception.Message)" }
} else {
    $csvWarnings += '[CSV 누락] squad\선수_능력치_기록표.csv 가 없습니다'
}

foreach ($name in $csvPlayerNames) { $rosterNames[$name] = $true }
$squadSnaps = @(Get-ChildItem -Path (Join-Path $root 'squad') -Filter *.json -ErrorAction SilentlyContinue |
    Sort-Object Name)
if ($squadSnaps.Count -gt 0) {
    try {
        $rs = Get-Content $squadSnaps[-1].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($pl in @($rs.players)) { if ($pl.name) { $rosterNames[$pl.name] = $true } }
    } catch { }
}

function NameKey([string]$name) {
    if (-not $name) { return '' }
    return (($name -replace '\s+', '').Trim().ToLowerInvariant())
}
function EditDistance([string]$a, [string]$b) {
    $a = NameKey $a; $b = NameKey $b
    $n = $a.Length; $m = $b.Length
    $prev = 0..$m
    for ($i = 1; $i -le $n; $i++) {
        $cur = New-Object int[] ($m + 1); $cur[0] = $i
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $cur[$j] = [Math]::Min([Math]::Min($cur[$j - 1] + 1, $prev[$j] + 1), $prev[$j - 1] + $cost)
        }
        $prev = $cur
    }
    return $prev[$m]
}
function Find-NameCorrection([string]$name) {
    if (-not $name -or $rosterNames.ContainsKey($name)) { return $null }
    $key = NameKey $name
    if (-not $key) { return $null }
    $limit = if ($key.Length -le 5) { 1 } elseif ($key.Length -le 10) { 2 } else { 3 }
    $candidates = @($rosterNames.Keys | ForEach-Object {
        $candidate = $_
        $distance = EditDistance $name $candidate
        if ($distance -le $limit) { [pscustomobject]@{ Name = $candidate; Distance = $distance } }
    } | Sort-Object Distance)
    if ($candidates.Count -eq 1 -or ($candidates.Count -gt 1 -and $candidates[0].Distance -lt $candidates[1].Distance)) {
        return $candidates[0].Name
    }
    return $null
}

# --- 경기 파일 읽기 + 검증 ------------------------------------------------
$files = @(Get-ChildItem -Path $matchDir -Filter *.json -ErrorAction SilentlyContinue | Sort-Object Name)
$chunks = @()
$warnings = @()
$warnings += $csvWarnings
$seen = @{}       # 중복 경기 감지용 (날짜+상대)
$matchObjs = @()  # digest 생성용 파싱 결과
$roleUsage = @{}  # 경기에서 실제로 쓰인 역할 코드 -> 처음 나온 파일

foreach ($f in $files) {
    $raw = Get-Content $f.FullName -Raw -Encoding UTF8
    try { $o = $raw | ConvertFrom-Json }
    catch { $warnings += "[JSON 오류] $($f.Name) — 건너뜁니다: $($_.Exception.Message)"; continue }

    foreach ($req in 'date', 'opponent', 'score') {
        if (-not $o.PSObject.Properties.Name.Contains($req)) { $warnings += "[필수 누락] $($f.Name) — '$req' 없음" }
    }
    if ($o.opponent) {
        if (-not $known.ContainsKey($o.opponent)) {
            $warnings += "[팀명 확인] $($f.Name) — '$($o.opponent)' 는 teams.json 에 없습니다 (오기? 새 팀?)"
        } elseif ($known[$o.opponent] -ne $true) {
            $warnings += "[표기 통일] $($f.Name) — '$($o.opponent)' -> '$($known[$o.opponent])' 로 통일하세요"
        }
    }
    # 선수 표기 — 가까운 표준명이 하나면 자동 교정하고, 원본 JSON은 보존한다.
    foreach ($pl in @($o.players)) {
        if ($pl.name) {
            $fixed = Find-NameCorrection ([string]$pl.name)
            if ($fixed) {
                $warnings += "[선수 자동 교정] $($f.Name) — '$($pl.name)' -> '$fixed'"
                $pl.name = $fixed
            }
        }
    }
    foreach ($sc in @($o.scorers)) {
        if ($sc.scorer -and -not $sc.own_goal) {
            $fixed = Find-NameCorrection ([string]$sc.scorer)
            if ($fixed) {
                $warnings += "[득점자 자동 교정] $($f.Name) — '$($sc.scorer)' -> '$fixed'"
                $sc.scorer = $fixed
            }
        }
        if ($sc.assist) {
            $fixed = Find-NameCorrection ([string]$sc.assist)
            if ($fixed) {
                $warnings += "[도움 선수 자동 교정] $($f.Name) — '$($sc.assist)' -> '$fixed'"
                $sc.assist = $fixed
            }
        }
    }
    if ($o.motm -and $o.motm.name) {
        $fixed = Find-NameCorrection ([string]$o.motm.name)
        if ($fixed) {
            $warnings += "[MOTM 자동 교정] $($f.Name) — '$($o.motm.name)' -> '$fixed'"
            $o.motm.name = $fixed
        }
    }

    # 선수 표기 (지니스카우트 표기가 표준)
    $names = @()
    foreach ($pl in @($o.players)) { if ($pl.name) { $names += $pl.name } }
    if ($o.motm -and $o.motm.name) { $names += $o.motm.name }
    foreach ($n in ($names | Select-Object -Unique)) {
        if ($rosterNames.Count -gt 0 -and -not $rosterNames.ContainsKey($n)) {
            $warnings += "[선수 확인] $($f.Name) — '$n' 은 스쿼드 명단에 없습니다 (잘린 이름? 오타? 신입?)"
        }
    }

    # scorers/assist — scorer는 own_goal 표시가 없으면 우리 선수여야 한다 (상대 득점 혼입 방지)
    foreach ($sc in @($o.scorers)) {
        if ($sc.scorer -and -not $sc.own_goal -and $rosterNames.Count -gt 0 -and
            -not $rosterNames.ContainsKey($sc.scorer)) {
            $warnings += "[자책골 확인] $($f.Name) — scorer '$($sc.scorer)' 는 스쿼드 명단에 없고 'own_goal' 표시도 없습니다 (상대 득점 혼입? 자책골 표기 누락?)"
        }
        if ($sc.assist -and $rosterNames.Count -gt 0 -and
            -not $rosterNames.ContainsKey($sc.assist)) {
            $warnings += "[선수 확인] $($f.Name) — assist '$($sc.assist)' 은 스쿼드 명단에 없습니다"
        }
    }

    # 역할 코드 수집 (기준 형태와 매칭되는지 나중에 확인)
    foreach ($pl in @($o.players)) {
        if ($pl.role) {
            $rc = ([string]$pl.role).Trim()
            if ($rc -and -not $roleUsage.ContainsKey($rc)) { $roleUsage[$rc] = $f.Name }
        }
    }

    # 포메이션 형식 (예: 4-2-3-1)
    foreach ($fk in 'formation', 'opponent_formation') {
        $fv = $o.$fk
        if ($fv -and ($fv -notmatch '^\d(-\d){1,4}$')) {
            $warnings += "[포메이션 형식] $($f.Name) — $fk '$fv' 이 '4-2-3-1' 같은 형식이 아닙니다"
        }
    }

    # 시즌
    if (-not $o.season) {
        $warnings += "[필수 누락] $($f.Name) — 'season' 없음 (예: 2025/26)"
    } elseif ($o.season -notmatch '^\d{4}/\d{2}$') {
        $warnings += "[형식 오류] $($f.Name) — season '$($o.season)' 는 YYYY/YY 형식이어야 합니다"
    }

    # 대회명
    if (-not $o.competition) {
        $warnings += "[필수 누락] $($f.Name) — 'competition' 없음"
    } elseif (-not $comps.ContainsKey($o.competition)) {
        $warnings += "[대회명 확인] $($f.Name) — '$($o.competition)' 는 competitions.json 에 없습니다 (오기? 새 대회?)"
    } elseif ($comps[$o.competition] -ne $true) {
        $warnings += "[표기 통일] $($f.Name) — 대회명 '$($o.competition)' -> '$($comps[$o.competition])' 로 통일하세요"
    }

    # 파일명 ↔ 내용 정합성 — 파일명이 date/opponent 조합과 다르면 저장 실수 가능성
    if ($o.date -and $o.opponent) {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $expected = "$($o.date)-vs-$($o.opponent)"
        if ($stem -notmatch ('^' + [regex]::Escape($expected) + '(-\d+)?$')) {
            $warnings += "[파일명 확인] $($f.Name) — 내용은 '$expected' 인데 파일명이 다릅니다"
        }
    }

    # 중복 경기 — 같은 날짜 + 같은 상대
    if ($o.date -and $o.opponent) {
        $key = "$($o.date)|$($o.opponent)"
        if ($seen.ContainsKey($key)) {
            $warnings += "[중복 경기 의심] $($f.Name) — '$($seen[$key])' 와 날짜·상대가 같습니다"
        } else {
            $seen[$key] = $f.Name
        }
    }

    # 수치 논리 — 화면을 잘못 읽었을 때 드러나는 모순
    foreach ($side in 'us', 'them') {
        $st = $null
        if ($o.team_stats) { $st = $o.team_stats.$side }
        if (-not $st) { continue }
        if ($null -ne $st.shots -and $null -ne $st.shots_on_target -and [double]$st.shots_on_target -gt [double]$st.shots) {
            $warnings += "[수치 논리] $($f.Name) — $side 유효슈팅 $($st.shots_on_target) 이 슈팅 $($st.shots) 보다 많습니다"
        }
        if ($null -ne $st.xg -and [double]$st.xg -lt 0) {
            $warnings += "[수치 논리] $($f.Name) — $side xG 가 음수입니다 ($($st.xg))"
        }
        if ($null -ne $st.possession -and ([double]$st.possession -lt 0 -or [double]$st.possession -gt 100)) {
            $warnings += "[수치 논리] $($f.Name) — $side 점유율이 0~100 범위 밖입니다 ($($st.possession))"
        }
        if ($null -ne $st.clear_cut_chances -and [double]$st.clear_cut_chances -lt 0) {
            $warnings += "[수치 논리] $($f.Name) — $side 완벽한 득점 기회가 음수입니다 ($($st.clear_cut_chances))"
        }
    }
    if ($o.team_stats -and $null -ne $o.team_stats.us.possession -and $null -ne $o.team_stats.them.possession) {
        $sum = [double]$o.team_stats.us.possession + [double]$o.team_stats.them.possession
        if ([math]::Abs($sum - 100) -gt 1) {
            $warnings += "[수치 논리] $($f.Name) — 점유율 합이 $sum% 입니다 (100 이어야 합니다)"
        }
    }

    # 득점자 수 = 득점
    if ($null -ne $o.scorers) {
        $goals = 0
        if ($o.score -and $null -ne $o.score.us) { $goals = [int]$o.score.us }
        if (@($o.scorers).Count -ne $goals) {
            $warnings += "[득점자 불일치] $($f.Name) — 득점 $goals / scorers $(@($o.scorers).Count)개"
        }
    }

    if ($o.uncertain -and @($o.uncertain).Count -gt 0) {
        $warnings += "[불확실] $($f.Name) — $(@($o.uncertain) -join ', ')"
    }
    # 자동 교정된 객체를 대시보드에도 반영한다. 원본 matches JSON은 보존한다.
    $chunks += ($o | ConvertTo-Json -Depth 20)
    $matchObjs += $o
}

$json = "[`n" + ($chunks -join ",`n") + "`n]"
if ($chunks.Count -eq 0) { $json = '[]' }

# --- dashboard.html 에 심기 ----------------------------------------------
function Splice([string]$text, [string]$startTag, [string]$endTag, [string]$body) {
    $s = $text.IndexOf($startTag)
    $e = $text.IndexOf($endTag)
    if ($s -lt 0 -or $e -lt 0) { throw "dashboard.html 에서 $startTag / $endTag 마커를 찾지 못했습니다." }
    return $text.Substring(0, $s + $startTag.Length) + "`n$body`n" + $text.Substring($e)
}

# 기준 형태 (모델) 읽기
$refJson = 'null'
$refFile = Join-Path $root 'reference-shape.json'
if (Test-Path $refFile) {
    $refRaw = (Get-Content $refFile -Raw -Encoding UTF8).Trim()
    try {
        $refObj = $refRaw | ConvertFrom-Json
        $refJson = $refRaw

        # 역할 코드 대조 — 안 맞으면 대시보드에서 "조용히" 고스트가 빠진다
        $slotRoles = @{}
        foreach ($s in @($refObj.slots)) { if ($s.role) { $slotRoles[([string]$s.role).Trim()] = $true } }

        foreach ($rc in $roleUsage.Keys) {
            if (-not $slotRoles.ContainsKey($rc)) {
                $warnings += "[역할 매칭] '$rc' ($($roleUsage[$rc])) 는 reference-shape.json 의 슬롯에 없습니다 — 기준 대비 비교에서 이 선수만 조용히 빠집니다"
            }
        }
    }
    catch { $warnings += "[JSON 오류] reference-shape.json — 무시합니다: $($_.Exception.Message)" }
}

# 전술 변경 (tactics/) — 언제 무엇을 바꿨는지
$tacChunks = @()
$tacObjs = @()
$tacIds = @{}
$tacFiles = @(Get-ChildItem -Path (Join-Path $root 'tactics') -Filter *.json -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($f in $tacFiles) {
    $raw = Get-Content $f.FullName -Raw -Encoding UTF8
    try { $t = $raw | ConvertFrom-Json }
    catch { $warnings += "[JSON 오류] tactics\$($f.Name) — 건너뜁니다: $($_.Exception.Message)"; continue }

    if (-not $t.date) { $warnings += "[전술] $($f.Name) — 'date' 없음 (변경을 적용한 날짜)" }
    elseif ($t.date -notmatch '^\d{4}-\d{2}-\d{2}$') { $warnings += "[전술] $($f.Name) — date '$($t.date)' 는 YYYY-MM-DD 형식이어야 합니다" }
    if (-not $t.change) { $warnings += "[전술] $($f.Name) — 'change'(무엇을 바꿨는지) 없음" }
    if ($t.season -and $t.season -notmatch '^\d{4}/\d{2}$') { $warnings += "[전술] $($f.Name) — season '$($t.season)' 형식 오류" }
    if ($t.id) {
        if ($tacIds.ContainsKey($t.id)) { $warnings += "[전술] $($f.Name) — id '$($t.id)' 가 '$($tacIds[$t.id])' 와 중복입니다" }
        else { $tacIds[$t.id] = $f.Name }
    }

    $tacChunks += $raw.Trim()
    $tacObjs += $t
}
$tacJson = if ($tacChunks.Count -eq 0) { '[]' } else { "[`n" + ($tacChunks -join ",`n") + "`n]" }

# 가설 (hypotheses/) — 해석을 남기는 곳
$hypChunks = @()
$hypObjs = @()
$hypIds = @{}
$validStatus = @('open', 'supported', 'rejected', 'stale')
$hypFiles = @(Get-ChildItem -Path (Join-Path $root 'hypotheses') -Filter *.json -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($f in $hypFiles) {
    $raw = Get-Content $f.FullName -Raw -Encoding UTF8
    try { $h = $raw | ConvertFrom-Json }
    catch { $warnings += "[JSON 오류] hypotheses\$($f.Name) — 건너뜁니다: $($_.Exception.Message)"; continue }

    if (-not $h.id) { $warnings += "[가설] $($f.Name) — 'id' 없음" }
    elseif ($hypIds.ContainsKey($h.id)) { $warnings += "[가설] $($f.Name) — id '$($h.id)' 가 '$($hypIds[$h.id])' 와 중복입니다" }
    else { $hypIds[$h.id] = $f.Name }

    if (-not $h.claim) { $warnings += "[가설] $($f.Name) — 'claim' 없음" }
    if (-not $h.falsify) {
        $warnings += "[가설] $($f.Name) — **falsify(반증 조건)가 없습니다.** 반증 조건 없는 가설은 지지 근거만 모으게 됩니다"
    }
    if (-not $h.basis -or @($h.basis).Count -eq 0) { $warnings += "[가설] $($f.Name) — 'basis'(근거)가 비어 있습니다" }
    if ($h.status -and $validStatus -notcontains $h.status) {
        $warnings += "[가설] $($f.Name) — status '$($h.status)' 는 open/supported/rejected/stale 중 하나여야 합니다"
    }

    # 열린 가설이 몇 경기째 확인되지 않았는지
    if ($h.status -eq 'open' -and $h.created) {
        $since = @($matchObjs | Where-Object { $_.date -and $_.date -gt $h.created }).Count
        $done = @($h.checked).Count
        if ($since -ge 3 -and $done -eq 0) {
            $warnings += "[가설 미확인] $($h.id) — 생성 이후 $since 경기가 지났는데 확인 기록이 없습니다"
        }
    }

    $hypChunks += $raw.Trim()
    $hypObjs += $h
}
$hypJson = if ($hypChunks.Count -eq 0) { '[]' } else { "[`n" + ($hypChunks -join ",`n") + "`n]" }

$html = Get-Content $dashboard -Raw -Encoding UTF8
$html = Splice $html '/*DATA_START*/'   '/*DATA_END*/'   "const MATCHES = $json;"
$html = Splice $html '/*REFERENCES_START*/' '/*REFERENCES_END*/' "const REFERENCES = $refJson;"
$attributesJson = if ($csvAttributes) { $csvAttributes | ConvertTo-Json -Depth 8 } else { '{}' }
$html = Splice $html '/*ATTRIBUTES_START*/' '/*ATTRIBUTES_END*/' "const ATTRIBUTES = $attributesJson;"
$html = Splice $html '/*HYP_START*/' '/*HYP_END*/' "const HYPOTHESES = $hypJson;"
$html = Splice $html '/*TACTIC_START*/' '/*TACTIC_END*/' "const TACTICS = $tacJson;"
$rulesJson = 'null'
$rulesFile = Join-Path $root 'comment-rules.json'
if (Test-Path $rulesFile) {
    $rulesRaw = (Get-Content $rulesFile -Raw -Encoding UTF8).Trim()
    try { $null = $rulesRaw | ConvertFrom-Json; $rulesJson = $rulesRaw }
    catch { $warnings += "[JSON 오류] comment-rules.json — 자동 코멘트를 끕니다: $($_.Exception.Message)" }
}
$html = Splice $html '/*RULES_START*/' '/*RULES_END*/' "const COMMENT_RULES = $rulesJson;"

[System.IO.File]::WriteAllText($dashboard, $html, (New-Object System.Text.UTF8Encoding $false))

# --- 스크린샷 → JSON 프롬프트 생성 -----------------------------------------
$teamsObj = Get-Content $teamsFile -Raw -Encoding UTF8 | ConvertFrom-Json
$ourTeam = $teamsObj.our_team
if (-not $ourTeam) { $ourTeam = '우리 팀' }
$teamList = @($teamsObj.teams.PSObject.Properties.Name | Where-Object { $_ -ne $ourTeam } | Sort-Object)

$compList = @()
if (Test-Path $compFile) {
    $compList = @((Get-Content $compFile -Raw -Encoding UTF8 | ConvertFrom-Json).competitions.PSObject.Properties.Name)
}

    # 선수 목록은 스냅샷을 우선하고, 새 시즌 초기화 상태에서는 능력치 CSV를 쓴다.
$playerList = @($csvPlayerNames)

    # 다른 AI 에게 스크린샷을 맡길 때 쓰는 프롬프트 — 표준 목록이 항상 최신으로 유지된다
    $pp = New-Object System.Text.StringBuilder
    function P([string]$s = '') { [void]$pp.AppendLine($s) }
    P "# FM26 경기 스크린샷 → JSON 변환 지시서"
    P ""
    P "생성 $(Get-Date -Format 'yyyy-MM-dd') · build.ps1 이 자동 생성한다. **직접 고치지 않는다.**"
    P "이 파일 전체를 복사해 다른 AI 에게 붙여넣고, FM 경기 화면 스크린샷을 함께 올린다."
    P ""
    P "---"
    P ""
    P "너는 FM26 경기 화면을 읽어 JSON 으로 옮기는 도구다. **설명은 하지 않는다.**"
    P "**출력은 딱 두 부분이다: 저장할 파일명 한 줄, 그다음 JSON 코드블록.** 그 외의 말은 덧붙이지 않는다."
    P ""
    P "## 절대 규칙"
    P ""
    P "1. **화면에서 확실히 읽히지 않는 값은 지어내지 않는다.** 그 필드를 통째로 빼고,"
    P '   경로를 `uncertain` 배열에 적는다. 예: `["team_stats.them.possession"]`'
    P "2. **날짜·상대·스코어·xG 중 하나라도 불확실하면 JSON 을 만들지 말고 무엇이 안 보이는지 되묻는다.**"
    P "3. 팀명·대회명·선수명은 아래 표준 목록의 표기를 **그대로** 쓴다. 목록에 없으면 화면에 보이는 대로 쓰고 ``uncertain`` 에 적는다."
    P "4. 모르는 항목은 비운다. 0 으로 채우지 않는다."
    P "5. **이름이 말줄임표(``...``)나 중간에서 잘려 보이면**, 아래 `표준 표기 · 선수` 목록에서 그 앞부분으로"
    P "   시작하는 이름이 하나뿐이면 전체 이름으로 채운다. 후보가 둘 이상이면 채우지 않고 ``uncertain`` 에 적는다."
    P "6. **선수명이 표준 목록과 글자 하나·두 개 정도 다르게 읽혔더라도**, 표준 목록에서 가장 가까운 후보가 정확히 하나면"
    P "   그 표준명으로 교정한다. 예: `슘쿠투 마가사` → `숭궁투 마가사`. 후보가 여러 개면 추측하지 말고 원문을 유지하며"
    P "   해당 경로를 ``uncertain`` 에 적는다. 이 규칙은 `players`, `scorers.scorer`, `scorers.assist`, `motm.name` 모두에 적용한다."
    P "7. **경기 이벤트 목록에서 왼쪽 정렬(아이콘이 텍스트 앞)이면 우리 득점, 오른쪽으로 들여쓰기(아이콘이 텍스트 뒤)면"
    P "   상대 득점이다.** 왼쪽에 있는데 이름이 우리 스쿼드에 없으면 **자책골**이다 —"
    P '   `scorers` 에 `"own_goal": true` 를 붙이고 `scorer` 에는 실제로 넣은 상대 선수 이름을 그대로 적는다.'
    P "   아이콘 색이 보통 득점과 다르게 표시되는 것도(붉은색 등) 자책골 신호다."
    P "   왼쪽/오른쪽 구분이 애매하거나 자책골인지 확신이 안 서면 지어내지 말고 ``uncertain`` 에 적어 되묻는다."
    P "   **상대 득점(오른쪽 정렬)은 `scorers` 에 넣지 않는다** — 우리 득점만 담는 배열이다."
    P ""
    P "## 출력 형식"
    P ""
    P '```json'
    P '{'
    P '  "date": "2025-10-25",'
    P '  "season": "2025/26",'
    P '  "competition": "프리미어리그",'
    P '  "opponent": "에버턴",'
    P '  "venue": "home",'
    P '  "opponent_formation": "4-3-3",'
    P '  "formation": "4-2-3-1",'
    P '  "score": { "us": 2, "them": 1 },'
    P '  "team_stats": {'
    P '    "us":   { "xg": 1.85, "shots": 14, "shots_on_target": 6, "possession": 55, "corners": 5, "clear_cut_chances": 2 },'
    P '    "them": { "xg": 0.90, "shots": 9,  "shots_on_target": 3, "possession": 45, "corners": 3, "clear_cut_chances": 1 }'
    P '  },'
    P '  "scorers": [ { "scorer": "에디 은케티아", "minute": 23, "assist": "애덤 와튼" } ],'
    P '  "players": [ { "no": 8, "name": "애덤 와튼", "role": "DLP", "rating": 7.4 } ],'
    P '  "motm": { "name": "애덤 은케티아", "rating": 7.9 },'
    P '  "notes": "",'
    P '  "uncertain": []'
    P '}'
    P '```'
    P ""
    P "- ``season`` 은 ``YYYY/YY``. 날짜가 7월 이후면 그 해가 시즌 시작 연도다."
    P "- ``venue`` 는 ``home`` 또는 ``away``."
    P "- ``scorers`` 는 **``us`` 득점만** 넣는다 (상대 득점 넣지 않음). ``assist`` 는 확인될 때만 넣는다."
    P "- 자책골(상대 선수가 우리 골을 넣음)은 ``\"own_goal\": true`` 를 붙여서 넣는다."
    P '  예: `{ "scorer": "상대선수명", "minute": 60, "own_goal": true }`'
    P "- ``players`` 는 **선발 11명 이름만이라도** 넣는다. 평점은 보이는 선수만."
    P "- 슈팅·점유율이 안 보이면 그 키를 뺀다. 유효슈팅이 슈팅보다 클 수 없고, 점유율 합은 100 이다."
    P "- ``clear_cut_chances`` 는 화면의 '완벽한 득점 기회' 값이다. 안 보이면 키를 뺀다."
    P ""
    P "## 파일명"
    P ""
    P "JSON 코드블록 **바로 위에**, 아래 형식 그대로 한 줄만 적는다 (백틱 포함, 다른 말 없이):"
    P ""
    P "``YYYY-MM-DD-vs-상대명.json``"
    P ""
    P "예: ``2025-10-25-vs-에버턴.json``"
    P ""
    P "- 상대명은 위 `"출력 형식`"에서 채운 ``opponent`` 값과 정확히 같아야 한다 (표기 다르게 지어내지 않는다)."
    P "- 같은 시즌에 같은 날짜·같은 상대 경기가 이미 있을 수 있는 경우(컵 대회 재경기 등)에는"
    P "  파일명 끝에 ``-2``, ``-3`` 처럼 번호를 붙이라고 안내만 하고, 실제 파일이 이미 있는지는"
    P "  AI가 알 수 없으니 **감독이 저장 직전에 직접 확인**한다."
    P ""
    P "## 표준 표기"
    P ""
    P "**대회** — " + ($compList -join ' · ')
    P ""
    P "**팀** — " + ($teamList -join ' · ')
    P ""
    P "**선수** — " + ($playerList -join ' · ')
    [System.IO.File]::WriteAllText((Join-Path $root 'screenshot-prompt.md'), $pp.ToString(), (New-Object System.Text.UTF8Encoding $false))

# --- digest.md 생성 --------------------------------------------------------
# 분석할 때 matches/ 를 전부 읽지 않아도 되도록 요약본을 만든다.
$sb = New-Object System.Text.StringBuilder
function W([string]$s = '') { [void]$sb.AppendLine($s) }
function Res($m) {
    if ([int]$m.score.us -gt [int]$m.score.them) { return 'W' }
    if ([int]$m.score.us -lt [int]$m.score.them) { return 'L' }
    return 'D'
}
function Nz($v) { if ($null -eq $v) { return 0.0 } return [double]$v }
function R1($v) { return ([math]::Round([double]$v, 1)).ToString() }
function SeasonOf($m) { if ($m.season) { return $m.season } return '미분류' }
function CompOf($m) { if ($m.competition) { return $m.competition } return '미분류' }

W "# 시즌 다이제스트"
W ""
W "생성 $(Get-Date -Format 'yyyy-MM-dd HH:mm') · build.ps1 이 자동 생성한다. **직접 고치지 않는다.**"
W ""
W "분석할 때는 ``matches/`` 를 전부 읽지 말고 이 파일을 먼저 읽는다."
W "특정 경기를 파고들어야 할 때만 그 경기 원본 하나를 연다."
W "수치는 Fact, 합계·차이·추세는 Inference, 가설은 ``hypotheses/`` 원본을 본다."
W ""

if ($matchObjs.Count -eq 0) {
    W "경기 기록이 없다."
} else {
    $seasons = @($matchObjs | ForEach-Object { SeasonOf $_ } | Select-Object -Unique | Sort-Object)
    $recentSeasons = @($seasons | Select-Object -Last 2)   # 이 두 시즌만 상세, 그 이전은 요약만 (digest.md 비대화 방지)
    foreach ($s in $seasons) {
        $ms = @()
        foreach ($m in $matchObjs) { if ((SeasonOf $m) -eq $s) { $ms += $m } }
        $ms = @($ms | Sort-Object { $_.date })

        $w = 0; $d = 0; $l = 0; $gf = 0; $ga = 0; $xf = 0.0; $xa = 0.0; $noXg = 0
        foreach ($m in $ms) {
            switch (Res $m) { 'W' { $w++ } 'D' { $d++ } 'L' { $l++ } }
            $gf += [int]$m.score.us; $ga += [int]$m.score.them
            $ux = $null; $tx = $null
            if ($m.team_stats) { $ux = $m.team_stats.us.xg; $tx = $m.team_stats.them.xg }
            if ($null -eq $ux) { $noXg++ }
            $xf += (Nz $ux); $xa += (Nz $tx)
        }

        W "## $s · $($ms.Count)경기"
        W ""
        W "- $($w)승 $($d)무 $($l)패 · 승점 $($w * 3 + $d) · 득실 ${gf}:${ga} ($(if ($gf - $ga -ge 0) { '+' })$($gf - $ga))"
        W "- xG $(R1 $xf) 대 $(R1 $xa) · 실득점은 xG 대비 $(if ($gf - $xf -ge 0) { '+' })$(R1 ($gf - $xf))"
        if ($noXg -gt 0) { W "- (xG 가 없는 경기 $noXg 개는 0 으로 합산됨 — 합계를 그대로 신뢰하지 말 것)" }
        W ""

        if ($recentSeasons -notcontains $s) {
            W "- (지난 시즌 상세 표는 생략 — 최근 2시즌만 상세 유지. 필요하면 원본 경기 파일이나 dashboard.html 참고)"
            W ""
            continue
        }

        # 대회별
        $seasonComps = @($ms | ForEach-Object { CompOf $_ } | Select-Object -Unique)
        if ($seasonComps.Count -gt 1) {
            W "### 대회별"
            W ""
            W "| 대회 | 경기 | 승 | 무 | 패 | 승점 | 득실 | xG |"
            W "|---|---|---|---|---|---|---|---|"
            foreach ($c in $seasonComps) {
                $g = @($ms | Where-Object { (CompOf $_) -eq $c })
                $cw = 0; $cd = 0; $cl = 0; $cgf = 0; $cga = 0; $cxf = 0.0; $cxa = 0.0
                foreach ($m in $g) {
                    switch (Res $m) { 'W' { $cw++ } 'D' { $cd++ } 'L' { $cl++ } }
                    $cgf += [int]$m.score.us; $cga += [int]$m.score.them
                    if ($m.team_stats) { $cxf += (Nz $m.team_stats.us.xg); $cxa += (Nz $m.team_stats.them.xg) }
                }
                W "| $c | $($g.Count) | $cw | $cd | $cl | $($cw * 3 + $cd) | ${cgf}:${cga} | $(R1 $cxf)/$(R1 $cxa) |"
            }
            W ""
        }

        # 경기 목록 — 시즌 내 최근 10경기만 상세, 그 이전은 압축 (digest.md 비대화 방지)
        $recentN = 10
        $olderMs = @()
        $recentMs = $ms
        if ($ms.Count -gt $recentN) {
            $olderMs = @($ms | Select-Object -First ($ms.Count - $recentN))
            $recentMs = @($ms | Select-Object -Last $recentN)
        }

        if ($olderMs.Count -gt 0) {
            W "### 이전 경기 ($($olderMs.Count)경기 · 날짜·상대·스코어만, 세부는 원본 JSON 참고)"
            W ""
            W (($olderMs | ForEach-Object {
                $v = if ($_.venue -eq 'home') { '홈' } else { '원정' }
                "$($_.date) $(CompOf $_) $v $($_.opponent) $(Res $_) $($_.score.us)-$($_.score.them)"
            }) -join ' · ')
            W ""
        }

        W "### 경기 목록 (최근 $($recentMs.Count)경기 상세)"
        W ""
        W "| 날짜 | 대회 | 장소 | 상대 | 결과 | xG | 유효/슈팅 | 점유 | 비고 |"
        W "|---|---|---|---|---|---|---|---|---|"
        foreach ($m in $recentMs) {
            $venue = if ($m.venue -eq 'home') { '홈' } else { '원정' }
            $us = $null; $them = $null
            if ($m.team_stats) { $us = $m.team_stats.us; $them = $m.team_stats.them }
            $xg = '–'
            if ($us -and $null -ne $us.xg) { $xg = "$(R1 $us.xg)/$(R1 (Nz $them.xg))" }
            $sh = '–'
            if ($us -and $null -ne $us.shots) { $sh = "$($us.shots_on_target)/$($us.shots)" }
            $po = '–'
            if ($us -and $null -ne $us.possession) { $po = "$($us.possession)%" }
            $memo = @()
            if ([int]$m.score.them -eq 0) { $memo += '무실점' }
            if ($us -and $null -ne $us.clear_cut_chances -and [int]$us.clear_cut_chances -gt [int]$m.score.us) {
                $memo += "완벽 기회 $($us.clear_cut_chances) 중 $($m.score.us)골"
            }
            if ($m.motm) { $memo += "MOTM $($m.motm.name)" }
            if ($m.uncertain -and @($m.uncertain).Count -gt 0) { $memo += "불확실 $(@($m.uncertain).Count)건" }
            W "| $($m.date) | $(CompOf $m) | $venue | $($m.opponent) | $(Res $m) $($m.score.us)-$($m.score.them) | $xg | $sh | $po | $($memo -join ', ') |"
        }
        W ""

        # 홈 · 원정
        $venueSets = New-Object System.Collections.ArrayList
        [void]$venueSets.Add(@{ label = '전체'; set = $ms })
        [void]$venueSets.Add(@{ label = '홈'; set = @($ms | Where-Object { $_.venue -eq 'home' }) })
        [void]$venueSets.Add(@{ label = '원정'; set = @($ms | Where-Object { $_.venue -ne 'home' }) })
        W "### 홈 · 원정"
        W ""
        W "| 구분 | 경기 | 승 | 무 | 패 | 경기당 승점 | 득실 | 경기당 xG |"
        W "|---|---|---|---|---|---|---|---|"
        foreach ($vs in $venueSets) {
            $g = @($vs.set)
            if ($g.Count -eq 0) { W "| $($vs.label) | 0 | | | | | | |"; continue }
            $vw = 0; $vd = 0; $vl = 0; $vgf = 0; $vga = 0; $vxf = 0.0
            foreach ($m in $g) {
                switch (Res $m) { 'W' { $vw++ } 'D' { $vd++ } 'L' { $vl++ } }
                $vgf += [int]$m.score.us; $vga += [int]$m.score.them
                if ($m.team_stats) { $vxf += (Nz $m.team_stats.us.xg) }
            }
            W "| $($vs.label) | $($g.Count) | $vw | $vd | $vl | $([math]::Round(($vw * 3 + $vd) / $g.Count, 2)) | ${vgf}:${vga} | $([math]::Round($vxf / $g.Count, 2)) |"
        }
        W ""

        # 득점 · 도움 / 시간대
        $gt = @{}
        $bl = @('1-15', '16-30', '31-45', '46-60', '61-75', '76+')
        $blo = @(1, 16, 31, 46, 61, 76); $bhi = @(15, 30, 45, 60, 75, 999)
        $bf = @(0, 0, 0, 0, 0, 0)
        foreach ($m in $ms) {
            foreach ($s in @($m.scorers)) {
                if (-not $s) { continue }
                if ($s -is [string]) { $nm = ($s -replace "\s*\d+'\s*$", '').Trim(); $mi = $null }
                else { $nm = $s.scorer; $mi = $s.minute }
                if ($nm) {
                    if (-not $gt.ContainsKey($nm)) { $gt[$nm] = @{ g = 0; a = 0 } }
                    $gt[$nm].g++
                }
                if ($s -isnot [string] -and $s.assist) {
                    if (-not $gt.ContainsKey($s.assist)) { $gt[$s.assist] = @{ g = 0; a = 0 } }
                    $gt[$s.assist].a++
                }
                if ($null -ne $mi) { for ($i = 0; $i -lt 6; $i++) { if ($mi -ge $blo[$i] -and $mi -le $bhi[$i]) { $bf[$i]++ } } }
            }
        }
        if ($gt.Count -gt 0) {
            W "### 득점 · 도움"
            W ""
            W (($gt.GetEnumerator() | Sort-Object { -($_.Value.g + $_.Value.a) } | ForEach-Object { "$($_.Key) $($_.Value.g)골 $($_.Value.a)도움" }) -join ' · ')
            W ""
        }
        if (($bf | Measure-Object -Sum).Sum -gt 0) {
            W "### 득점 시간대"
            W ""
            W (((0..5) | ForEach-Object { "$($bl[$_]) $($bf[$_])" }) -join ' · ')
            W ""
        }

        # 선수 평점
        $pr = @{}
        foreach ($m in $ms) {
            foreach ($p in @($m.players)) {
                if (-not $p -or -not $p.name -or $null -eq $p.rating) { continue }
                if (-not $pr.ContainsKey($p.name)) { $pr[$p.name] = @() }
                $pr[$p.name] += [double]$p.rating
            }
        }
        if ($pr.Count -gt 0) {
            W "### 선수 평점 (기록된 선수만)"
            W ""
            W "| 선수 | 출전 | 평균 | 최고 | 최저 |"
            W "|---|---|---|---|---|"
            foreach ($k in ($pr.Keys | Sort-Object { ($pr[$_] | Measure-Object -Average).Average } -Descending)) {
                $v = $pr[$k]
                $st = $v | Measure-Object -Average -Maximum -Minimum
                W "| $k | $($v.Count) | $([math]::Round($st.Average, 2)) | $($st.Maximum) | $($st.Minimum) |"
            }
            W ""
        }
    }
}

# 전술 변경
if ($tacObjs.Count -gt 0) {
    W "## 전술 변경"
    W ""
    $allMs = @($matchObjs | Sort-Object { $_.date })
    foreach ($t in ($tacObjs | Sort-Object { $_.date } -Descending)) {
        W "**$($t.date)** — $($t.change)"
        if ($t.detail) { W "- $($t.detail)" }
        if ($t.reason) { W "- 바꾼 이유: $($t.reason)" }
        if ($t.expect) { W "- 기대한 변화: $($t.expect)" }

        $bef = @(@($allMs | Where-Object { $_.date -lt $t.date }) | Select-Object -Last 5)
        $aft = @(@($allMs | Where-Object { $_.date -ge $t.date }) | Select-Object -First 5)
        if ($bef.Count -eq 0 -or $aft.Count -eq 0) {
            W "- 전후 비교: 경기가 부족합니다 (이전 $($bef.Count) / 이후 $($aft.Count))"
        } else {
            $ppg = {
                param($g)
                $p = 0
                foreach ($m in $g) { switch (Res $m) { 'W' { $p += 3 } 'D' { $p += 1 } } }
                return [math]::Round($p / $g.Count, 2)
            }
            $xg = {
                param($g, $side)
                $s = 0.0
                foreach ($m in $g) { if ($m.team_stats) { $s += (Nz $m.team_stats.$side.xg) } }
                return [math]::Round($s / $g.Count, 2)
            }
            W "- 이전 $($bef.Count)경기 / 이후 $($aft.Count)경기 — 경기당 승점 $(& $ppg $bef) → $(& $ppg $aft) · xG $(& $xg $bef 'us') → $(& $xg $aft 'us') · 피xG $(& $xg $bef 'them') → $(& $xg $aft 'them')"
            if ($bef.Count -lt 3 -or $aft.Count -lt 3) { W "- **표본 3경기 미만 — 추세로 읽지 말 것**" }
        }
        W ""
    }
    W "상대 난이도가 섞여 있으므로 **인과가 아니라 상관**이다."
    W ""
}

# 가설
if ($hypObjs.Count -gt 0) {
    $openH = @($hypObjs | Where-Object { $_.status -eq 'open' })
    W "## 가설"
    W ""
    W "전체 $($hypObjs.Count)건 · 열림 $($openH.Count) · 지지 $(@($hypObjs | Where-Object { $_.status -eq 'supported' }).Count) · 기각 $(@($hypObjs | Where-Object { $_.status -eq 'rejected' }).Count)"
    W ""
    foreach ($h in $hypObjs) {
        W "**$($h.id)** ($($h.status), $($h.created) 생성) — $($h.claim)"
        W ""
        W "- 기각 조건: $($h.falsify)"
        if (@($h.checked).Count -gt 0) {
            foreach ($c in @($h.checked)) { W "- 확인 $($c.date) $($c.match): **$($c.verdict)** $($c.note)" }
        } else {
            W "- 확인 기록 없음"
        }
        if ($h.conclusion) { W "- 결론: $($h.conclusion)" }
        W ""
    }
    W "새 경기가 들어오면 **지지 근거보다 기각 조건을 먼저 확인한다.**"
    W ""
}

$digestPath = Join-Path $root 'digest.md'
[System.IO.File]::WriteAllText($digestPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))

# --- 전술 보드에 GAME_DATA·EVIDENCE 심기 -----------------------------------
$boardPath = Join-Path $root 'tactics-board.html'
$boardDone = $false
if (Test-Path $boardPath) {
    $dataDir = Join-Path $root 'data'
    $map = [ordered]@{
        CB = 'CB.json'; DLR = 'DLR.json'; DM = 'DM.json'; MC = 'MC.json'
        AMC = 'AMC.json'; AML_R = 'AML_R.json'; ST = 'ST.json'
        Player_Instructions = 'Player_Instructions.json'
        Team_instructions = 'Team_instructions.json'
        PPM = 'PPM.json'
    }
    $parts = @()
    foreach ($k in $map.Keys) {
        $f = Join-Path $dataDir $map[$k]
        if (Test-Path $f) { $parts += '"' + $k + '": ' + (Get-Content $f -Raw -Encoding UTF8).Trim() }
        else { $warnings += "[전술 보드] data\$($map[$k]) 가 없습니다" }
    }
    # 선수 명단·능력치는 감독이 관리하는 CSV를 빌드 시 전술 보드 형식으로 변환한다.
    if ($csvAttributes) { $parts += '"attributes": ' + ($csvAttributes | ConvertTo-Json -Depth 8).Trim() }
    else { $warnings += "[전술 보드] squad\선수_능력치_기록표.csv 를 읽지 못해 선수 명단이 비었습니다" }

    # 왼발/오른발 칸수 환산 기준 (모델 — 게임에서 측정된 값이 아니다). 없어도 경고하지 않는다 — 선택 파일.
    $footScaleFile = Join-Path $root 'foot-scale.json'
    if (Test-Path $footScaleFile) {
        try {
            $null = (Get-Content $footScaleFile -Raw -Encoding UTF8) | ConvertFrom-Json
            $parts += '"foot_scale": ' + (Get-Content $footScaleFile -Raw -Encoding UTF8).Trim()
        } catch { $warnings += "[전술 보드] foot-scale.json — JSON 오류: $($_.Exception.Message)" }
    }

    # 시즌 근거 — 전술 조언 프롬프트에 붙는다
    $ev = @()
    if ($matchObjs.Count -gt 0) {
        $ms = @($matchObjs | Sort-Object { $_.date })
        $w = 0; $d = 0; $l = 0; $gf = 0; $ga = 0; $xf = 0.0; $xa = 0.0
        foreach ($m in $ms) {
            switch (Res $m) { 'W' { $w++ } 'D' { $d++ } 'L' { $l++ } }
            $gf += [int]$m.score.us; $ga += [int]$m.score.them
            if ($m.team_stats) { $xf += (Nz $m.team_stats.us.xg); $xa += (Nz $m.team_stats.them.xg) }
        }
        $ev += "- $($ms.Count)경기 $($w)승 $($d)무 $($l)패 · 득실 ${gf}:${ga} · 경기당 xG $([math]::Round($xf / $ms.Count, 2)) 대 $([math]::Round($xa / $ms.Count, 2))"
        $hm = @($ms | Where-Object { $_.venue -eq 'home' }); $aw = @($ms | Where-Object { $_.venue -ne 'home' })
        if ($hm.Count -gt 0 -and $aw.Count -gt 0) {
            $hp = 0; foreach ($m in $hm) { switch (Res $m) { 'W' { $hp += 3 } 'D' { $hp += 1 } } }
            $ap = 0; foreach ($m in $aw) { switch (Res $m) { 'W' { $ap += 3 } 'D' { $ap += 1 } } }
            $ev += "- 홈 $($hm.Count)경기 경기당 승점 $([math]::Round($hp / $hm.Count, 2)) / 원정 $($aw.Count)경기 $([math]::Round($ap / $aw.Count, 2))"
        }
        $ev += "- 표본이 적으면 추세로 읽지 말 것 (현재 $($ms.Count)경기)"
    }
    $evText = ($ev -join "`n") -replace '\\', '\\\\' -replace '"', '\"' -replace "`r?`n", '\n'

    $board = Get-Content $boardPath -Raw -Encoding UTF8
    $board = Splice $board '/*GAMEDATA_START*/' '/*GAMEDATA_END*/' ("const GAME_DATA = {" + ($parts -join ', ') + "};")
    $board = Splice $board '/*EVIDENCE_START*/' '/*EVIDENCE_END*/' ('const EVIDENCE = "' + $evText + '";')
    [System.IO.File]::WriteAllText($boardPath, $board, (New-Object System.Text.UTF8Encoding $false))
    $boardDone = $true
}

# --- 결과 ------------------------------------------------------------------
Write-Host "경기 $($chunks.Count)개 · 선수 $($csvPlayerNames.Count)명 -> dashboard.html 갱신 완료" -ForegroundColor Green
Write-Host "digest.md 생성 완료 (경기 $($matchObjs.Count) · 가설 $($hypObjs.Count))" -ForegroundColor Green
if ($boardDone) { Write-Host "tactics-board.html 갱신 완료 (역할 데이터 + 선수 명단 + 시즌 근거)" -ForegroundColor Green }
Write-Host "screenshot-prompt.md 갱신 완료 (팀 $($teamList.Count) · 대회 $($compList.Count) · 선수 $($playerList.Count))" -ForegroundColor Green
if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "확인이 필요한 항목 $($warnings.Count)건:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}
