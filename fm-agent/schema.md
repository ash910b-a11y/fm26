# 경기 기록 규칙 (에이전트용)

FM 스크린샷을 JSON으로 옮길 때 **반드시** 아래 규칙을 지킨다.

## 저장 위치 / 파일명

```
fm-agent/screenshots/          원본 스크린샷 (절대 지우지 않는다)
fm-agent/matches/YYYY-MM-DD-vs-상대명.json
```

## 스키마

```json
{
  "date": "2026-08-08",
  "season": "2026/27",
  "competition": "프리미어리그",
  "opponent": "브렌트포드",
  "venue": "away",
  "score": { "us": 2, "them": 1 },
  "team_stats": {
    "us":   { "xg": 2.14, "shots": 15, "shots_on_target": 7, "possession": 58 },
    "them": { "xg": 1.80, "shots": 11, "shots_on_target": 4, "possession": 42 }
  },
  "scorers": [
    { "minute": 23, "scorer": "에디 은케티아", "assist": "예레미 피노" },
    { "minute": 71, "scorer": "예르겐 스트란 라르센" }
  ],
  "formation": "4-2-3-1",
  "players": [
    { "no": 88, "name": "코스타스 촐라키스", "role": "BGK", "rating": 7.7 }
  ],
  "notes": "후반 라인 내려앉으면서 압박이 끊김",
  "uncertain": ["team_stats.them.possession"],
  "source_screenshots": ["screenshots/2026-08-08-brentford-1.png"]
}
```

- `season`: **필수.** `YYYY/YY` 형식 (예: `"2025/26"`). 시즌이 넘어가면 통계가 섞이므로 반드시 적는다.
- `competition`: **필수.** `competitions.json` 의 표준 대회명과 대조한다. 목록에 없으면 저장 전에 물어본다.
- `venue`: `"home"` 또는 `"away"`
- `possession`: 퍼센트 숫자 (기호 없이)
- `scorers`: 득점 1개당 항목 1개. `scorer` 는 필수, `minute`·`assist` 는 확인될 때만 넣는다.
  도움을 준 선수를 모르면 `assist` 를 **생략한다.** 빈 문자열이나 추측을 넣지 않는다.
- **실점 원인(`concede_causes`)은 더 이상 쓰지 않는다.** 감독이 확인할 수 없는 경기가 많아 폐지했다.
  기록하지도, 묻지도, 집계하지도 않는다.
- `opponent_formation`: 상대 포메이션 (예: `"4-3-3"`). 확인되면 넣고, 아니면 생략.
- `players`: **선발 11명은 이름만이라도 넣는다.** `rating` 은 선택이라 비워도 되고,
  이름만 있으면 조합 승률·출전 승률이 계산된다. 평점은 특기할 선수만. 없으면 통째로 생략.
- `formation` / `players`: 포메이션 화면 스크린샷이 있을 때만. 없으면 통째로 생략.
- `passmap`: 패스맵 화면이 있을 때만. **반드시 `"approx": true`를 함께 적는다.**
  - `positions`: `{no, x, y}` — `x` 0=왼쪽 터치라인 · 100=오른쪽, `y` 0=우리 골라인 · 100=상대 골라인.
    화면의 숫자가 아니라 **눈으로 읽은 추정 좌표**다. 5 단위로 반올림해도 무방하다.
  - `links`: `{from, to, strength}` — **굵은 초록/연두 연결만** 기록한다 (strength 3=굵은 초록, 2=중간).
    가는 파란 선은 강도를 판별할 수 없으므로 **기록하지 않는다.** 패스 개수·성공률은 화면에 없다 — 절대 만들어내지 않는다.
- **경기 기록 화면은 좌/우 어느 쪽이 우리 팀인지 화면만 봐서는 알 수 없다.**
  홈이 왼쪽이라는 관례는 추정일 뿐이므로, 확신이 없으면 `uncertain`에 적고 감독에게 확인한다.
- 값이 화면에 없으면 그 키를 **빼거나** `null`. 절대 추정해서 채우지 않는다.

## 가설 (`hypotheses/*.json`)

경기 수치가 아니라 **해석**을 남기는 곳이다. Fact 는 `matches/`, Inference 는 어디에도
저장하지 않는다(데이터에서 매번 다시 계산된다). **Hypothesis 만 저장한다 — 안 하면 사라진다.**

```json
{
  "id": "H-002",
  "created": "2025-10-25",
  "season": "2025/26",
  "claim": "한 문장으로 된 주장",
  "basis": ["근거가 된 경기와 수치", "..."],
  "falsify": "이런 결과가 나오면 이 가설은 틀린 것이다",
  "status": "open",
  "checked": [
    { "date": "2025-11-02", "match": "번리", "verdict": "supports", "note": "..." }
  ],
  "conclusion": null
}
```

- **`falsify` 가 없는 가설은 만들지 않는다.** 반증 조건이 없으면 지지 근거만 모으는
  자기 확증 장치가 된다. build.ps1 이 경고한다.
- `status`: `open` · `supported` · `rejected` · `stale` 넷 중 하나.
- `verdict`: `supports` · `contradicts` · `inconclusive` 셋 중 하나.
- 새 경기가 저장되면 **열린 가설의 `falsify` 조건부터 확인한다.** 지지 근거를 먼저 찾지 않는다.
- 결론이 나면 `status` 를 바꾸고 `conclusion` 에 한 줄로 적는다. **틀린 가설도 지운다 대신 남긴다.**

## 전술 변경 (`tactics/*.json`)

언제 무엇을 바꿨는지 한 건씩 남긴다. 대시보드와 digest 가 **변경 전후 최대 5경기를 자동 비교**한다.

```json
{
  "id": "T-001",
  "date": "2025-08-20",
  "season": "2025/26",
  "change": "압박 강도 ↑",
  "detail": "리그 평균보다 높게. 수비 라인도 한 칸 올림",
  "reason": "상대 빌드업을 못 막아 피xG 가 컸음",
  "expect": "내주는 코너킥 감소, 피xG 감소"
}
```

- `date`(적용한 날짜)와 `change` 는 필수. 나머지는 선택.
- **전후 비교는 인과가 아니라 상관이다.** 상대 난이도가 섞여 있으므로 단정하지 않는다.
- 표본이 3경기 미만이면 대시보드가 경고한다. 그때는 추세로 말하지 않는다.

## 절대 규칙

1. **지어내지 않는다.** 화면에서 확실히 읽히지 않는 값은 `uncertain` 배열에 경로를 적는다.
   (예: `"team_stats.them.xg"`)
2. **핵심 수치(`date`, `opponent`, `score`, `xg`)가 불확실하면 저장하지 말고 사용자에게 되묻는다.**
   단, 감독이 "경기 기록이 없다"고 확인해 준 패스맵은 **`shapes/`에 형태로만** 저장한다.
   `matches/`에 넣으면 승패·xG 통계가 오염되므로 절대 넣지 않는다.
3. **팀명은 `teams.json`의 표준 표기와 대조**한다. 목록에 없는 이름이면 저장 전에
   "이 팀은 목록에 없습니다 — 오기인가요, 새 팀인가요?"라고 물어본다.
4. 원본 스크린샷은 `screenshots/`에 남기고 `source_screenshots`에 경로를 적는다.
5. 저장 후 `build.ps1`을 실행해 대시보드를 갱신한다.
