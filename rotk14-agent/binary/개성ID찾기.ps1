# 삼국지14 데이터 파일에서 개성 ID 표를 찾는다.
# 사용법:  powershell -ExecutionPolicy Bypass -File 개성ID찾기.ps1 "C:\경로\데이터파일"
param([Parameter(Mandatory=$true)][string]$Path)

if (-not (Test-Path $Path)) { Write-Host "파일이 없다: $Path"; exit 1 }

# ID 를 이미 아는 개성들. 이 이름들이 파일 어디에 있는지 찾는다.
$known = @{ "견수"=7; "낭비"=31; "신안"=48; "산전"=69; "응원"=96; "신장"=150 }
# 위치 확인용으로 몇 개 더 본다.
$extra = @("간웅","통찰","복룡","효웅","견뢰","지리","질주","소탕","호걸","단기")

Write-Host "파일 읽는 중... ($([math]::Round((Get-Item $Path).Length/1MB,1)) MB)"
$bytes = [System.IO.File]::ReadAllBytes($Path)
Write-Host "$($bytes.Length) 바이트`n"

function Find-All([byte[]]$hay, [byte[]]$needle) {
    $hits = New-Object System.Collections.Generic.List[int]
    $limit = $hay.Length - $needle.Length
    for ($i = 0; $i -le $limit; $i++) {
        if ($hay[$i] -ne $needle[0]) { continue }
        $ok = $true
        for ($j = 1; $j -lt $needle.Length; $j++) {
            if ($hay[$i+$j] -ne $needle[$j]) { $ok = $false; break }
        }
        if ($ok) { [void]$hits.Add($i); if ($hits.Count -ge 8) { break } }
    }
    return $hits
}

Write-Host "=== ID 를 아는 개성 ==="
foreach ($name in $known.Keys | Sort-Object) {
    $pat = [System.Text.Encoding]::Unicode.GetBytes($name)   # UTF-16LE
    $hits = Find-All $bytes $pat
    $where = if ($hits.Count -eq 0) { "못 찾음" } else { ($hits | ForEach-Object { "0x{0:X}" -f $_ }) -join ", " }
    Write-Host ("{0,-6} ID={1,-4} -> {2}" -f $name, $known[$name], $where)
}

Write-Host "`n=== ID 를 모르는 개성 ==="
foreach ($name in $extra) {
    $pat = [System.Text.Encoding]::Unicode.GetBytes($name)
    $hits = Find-All $bytes $pat
    $where = if ($hits.Count -eq 0) { "못 찾음" } else { ($hits | ForEach-Object { "0x{0:X}" -f $_ }) -join ", " }
    Write-Host ("{0,-6}          -> {1}" -f $name, $where)
}

Write-Host "`n출력 전체를 그대로 복사해서 붙여넣으면 된다."
