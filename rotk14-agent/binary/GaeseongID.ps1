# 삼국지14 데이터에서 개성 이름을 찾는다.
# 파일 하나든 폴더 전체든 받는다. 폴더면 안의 모든 파일을 훑는다.
param([Parameter(Mandatory=$true)][string]$Path)

$known = [ordered]@{ "견수"=7; "낭비"=31; "신안"=48; "산전"=69; "응원"=96; "신장"=150 }
$extra = @("간웅","통찰","복룡","효웅","견뢰","지리","질주","소탕","호걸","단기","방원","안행","어린","철벽")
$all   = @($known.Keys) + $extra

if (Test-Path $Path -PathType Container) {
    $files = Get-ChildItem -Path $Path -File -Recurse | Sort-Object Length -Descending
    Write-Host "폴더: $Path"
} else {
    $files = @(Get-Item $Path)
    Write-Host "파일: $Path"
}
Write-Host "대상 $($files.Count)개, 총 $([math]::Round(($files | Measure-Object Length -Sum).Sum/1MB,1)) MB"
Write-Host "훑는 중...`n"

$found = @{}
$scanned = 0
foreach ($f in $files) {
    if ($f.Length -lt 64 -or $f.Length -gt 400MB) { continue }
    $scanned++
    try {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        # UTF-16LE 로 통째로 해석한 뒤 문자열 검색 — 바이트 루프보다 훨씬 빠르다
        $text = [System.Text.Encoding]::Unicode.GetString($bytes)
    } catch { continue }

    foreach ($name in $all) {
        $i = $text.IndexOf($name)
        if ($i -ge 0) {
            if (-not $found.ContainsKey($f.Name)) { $found[$f.Name] = @{} }
            if (-not $found[$f.Name].ContainsKey($name)) {
                $found[$f.Name][$name] = $i * 2   # 문자 위치 -> 바이트 오프셋
            }
        }
    }
}

Write-Host "훑은 파일: $scanned 개`n"

if ($found.Count -eq 0) {
    Write-Host "=== 아무것도 못 찾았다 ==="
    Write-Host "개성 이름이 UTF-16LE 로 들어있지 않거나 압축되어 있다."
    Write-Host "여기서 포기하고 게임에서 직접 만드는 게 맞다."
} else {
    # 많이 걸린 파일부터
    foreach ($fname in ($found.Keys | Sort-Object { -$found[$_].Count })) {
        $hits = $found[$fname]
        Write-Host "=== $fname  ($($hits.Count)개 발견) ==="
        foreach ($name in $all) {
            if ($hits.ContainsKey($name)) {
                $id = if ($known.Contains($name)) { "ID=$($known[$name])" } else { "" }
                Write-Host ("  {0,-6} {1,-8} 0x{2:X}  ({2})" -f $name, $id, $hits[$name])
            }
        }
        Write-Host ""
    }
    Write-Host "ID 를 아는 여섯 개(견수7 낭비31 신안48 산전69 응원96 신장150)가"
    Write-Host "한 파일에 다 있고 간격이 일정하면 성공이다."
}

Write-Host "`n출력 전체를 복사해서 붙여넣으면 된다."
