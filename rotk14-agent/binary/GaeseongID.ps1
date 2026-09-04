# 삼국지14 데이터에서 개성 이름을 찾는다. 인코딩 세 가지를 모두 시도한다.
param([Parameter(Mandatory=$true)][string]$Path)

$known = [ordered]@{ "견수"=7; "낭비"=31; "신안"=48; "산전"=69; "응원"=96; "신장"=150 }
# 철벽은 흔한 단어라 오탐이 잦다. 개성 이름 위주로 본다.
$extra = @("간웅","통찰","복룡","효웅","견뢰","지리","질주","소탕","호걸","단기","봉시","방원","안행")
$all   = @($known.Keys) + $extra

$encs = [ordered]@{
    "UTF-16LE" = [System.Text.Encoding]::Unicode
    "UTF-8"    = [System.Text.Encoding]::UTF8
    "CP949"    = [System.Text.Encoding]::GetEncoding(949)
}

if (Test-Path $Path -PathType Container) {
    $files = Get-ChildItem -Path $Path -File -Recurse | Sort-Object Length -Descending
    Write-Host "폴더: $Path"
} else {
    $files = @(Get-Item $Path); Write-Host "파일: $Path"
}
Write-Host "대상 $($files.Count)개, 총 $([math]::Round(($files | Measure-Object Length -Sum).Sum/1MB,1)) MB"
Write-Host "인코딩 3종으로 훑는 중...`n"

$rows = New-Object System.Collections.Generic.List[object]
$scanned = 0
foreach ($f in $files) {
    if ($f.Length -lt 64 -or $f.Length -gt 400MB) { continue }
    $scanned++
    try { $bytes = [System.IO.File]::ReadAllBytes($f.FullName) } catch { continue }
    foreach ($encName in $encs.Keys) {
        try { $text = $encs[$encName].GetString($bytes) } catch { continue }
        $mul = if ($encName -eq "UTF-16LE") { 2 } else { 1 }
        foreach ($name in $all) {
            $i = $text.IndexOf($name)
            if ($i -ge 0) {
                $rows.Add([pscustomobject]@{
                    File=$f.Name; Enc=$encName; Name=$name
                    Id=$(if ($known.Contains($name)) { $known[$name] } else { "" })
                    Off=$i*$mul
                })
            }
        }
    }
}

Write-Host "훑은 파일: $scanned 개, 발견 $($rows.Count) 건`n"

if ($rows.Count -eq 0) {
    Write-Host "=== 아무것도 못 찾았다 ==="
    Write-Host "개성 이름이 평문으로 들어있지 않다. 압축되어 있을 가능성이 높다."
    Write-Host "여기서 접고 게임에서 직접 만드는 것이 맞다."
} else {
    $g = $rows | Group-Object File, Enc | Sort-Object Count -Descending
    foreach ($grp in $g) {
        Write-Host "=== $($grp.Name)  —  $($grp.Count)개 ==="
        foreach ($r in ($grp.Group | Sort-Object Off)) {
            Write-Host ("  {0,-6} {1,-5} 0x{2:X} ({2})" -f $r.Name, $r.Id, $r.Off)
        }
        Write-Host ""
    }
    Write-Host "한 파일·한 인코딩에서 여러 개가 함께 나왔다면 그게 표다."
    Write-Host "하나만 덜렁 나온 것은 우연일 가능성이 높다."
}

Write-Host "`n출력 전체를 복사해서 붙여넣으면 된다."
