# 도구 정비 안내

**`dashboard.html`·`tactics-board.html`·`build.ps1` 을 고치기 전에 이 파일을 읽는다.**
평소 브리핑·분석 세션에서는 읽을 필요가 없다 (그래서 `CLAUDE.md` 에서 분리했다).

---

## 절대 건드리지 않는 것

**`dashboard.html` 을 통째로 새로 만들지 않는다.** 데이터는 build.ps1 이 아래 마커 사이에 심는다.
마커 **안쪽**을 직접 편집하면 다음 build 때 사라지고, 파일을 재생성하면 필터·대회별 요약·
선수 평점·패스맵·기준 오버레이·자동 코멘트 섹션이 전부 날아간다.

```
/*REF_START*/ … /*REF_END*/        기준 형태
/*HYP_START*/ … /*HYP_END*/        가설
/*DATA_START*/ … /*DATA_END*/      경기 데이터
/*TACTIC_START*/ … /*TACTIC_END*/  전술 변경 기록
/*RULES_START*/ … /*RULES_END*/    자동 코멘트 규칙 (comment-rules.json)
```

`screenshot-prompt.md` 는 `build.ps1` 이 팀·대회·선수 표준 목록을 반영해 생성한다.
`tactics-board.html` 에는 `/*GAMEDATA_START*/` 와 `/*EVIDENCE_START*/` 가 있어 `data/` 의
역할 정의·선수 능력치·시즌 근거가 주입된다. 목록을 바꾸려면 이 블록이 아니라 원본 파일을 고친다.

마커 **바깥**의 HTML·CSS·JS 는 자유롭게 고쳐도 된다.

**`.ps1` 을 새로 만들거나 고치면 반드시 UTF-8 BOM 으로 다시 저장한다.**
BOM 이 없으면 Windows PowerShell 5.1 이 한글을 깨뜨려 파싱 오류가 난다.

```powershell
$p = "경로.ps1"
$t = [System.IO.File]::ReadAllText($p, (New-Object System.Text.UTF8Encoding $false))
[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding $true))
```

`$home` 처럼 PowerShell 예약 변수는 쓰지 않는다. `$w승` 같이 한글이 변수명에 붙는 보간도
피한다 (`$($w)승` 으로 쓴다).

---

## 작업 방식

1. **파일을 통째로 다시 쓰지 않는다.** 바뀌는 부분만 고친다.
2. **코드를 채팅에 출력하지 않는다.** 파일에 직접 적용하고, 무엇을 왜 바꿨는지만 말한다.
3. **큰 파일을 통째로 읽지 않는다.** Grep 으로 앵커를 찾아 그 근처만 고친다.
4. **기존 HTML·CSS·JS 구조를 유지한다.** 새 기능도 같은 파일 안에 넣는다.
   **별도 JS 파일로 쪼개지 않는다** — 단일 파일·더블클릭 실행이 이 도구의 전제이고,
   쪼개도 토큰은 줄지 않는다 (수정 비용은 파일 크기가 아니라 바뀌는 양에 비례한다).
5. **JSON 스키마는 기존 구조를 유지하고 필요한 필드만 추가한다.**
6. **기존 기능과의 호환성이 최우선이다.** 새 기능 때문에 이미 되던 게 깨지면 실패다.
7. **JSON 데이터**(역할·팀명·규칙 등)는 그때그때 고쳐도 된다.
   **HTML·스크립트는 즉시 고치지 말고 모아뒀다가 한 번에 처리한다.**
8. 고친 뒤에는 `build.ps1` 을 돌려 경고를 확인하고, 대시보드를 브라우저로 열어
   **콘솔 에러 0** 을 확인한다.

---

## build.ps1 이 잡아주는 것

JSON 오류 · 필수 필드 누락(date/opponent/score/season/competition) · 팀명/대회명 표기 ·
**선수명이 CSV 명단에 없음** · season 형식 · 포메이션 형식 · **파일명 ↔ date/opponent 불일치** ·
**중복 경기(날짜+상대)** · **수치 논리**(유효슈팅>슈팅, xG 음수, 점유율 합·범위) ·
**득점자 수 불일치** · 자책골 표시 없는 외부 득점자 · 역할 코드 미매칭 · `uncertain` 목록

`uncertain` 값을 분석에서 확정값처럼 쓰지 않는 것은 **스크립트가 못 잡는다.**
그건 코치가 지켜야 할 규칙이며 `coach.md` 에 있다.

---

## 미완성 작업

`TODO.md` 를 본다. **새 기능을 논의하기 전에 거기부터 확인한다.**
