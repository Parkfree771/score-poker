# 스토어 등록 문안 (Play Console / App Store Connect)

> 제목·설명은 스토어 등록 시 복사해 쓰는 초안이다. 확정 앱 이름이 정해지면 교체할 것.
> ⚠️ "베팅 없음"은 심사 통과에 중요한 문구다 — 도박 카테고리로 오분류되지 않게 한다.

## 공통

| 항목 | 값 |
|---|---|
| 앱 이름 | Score Poker (가칭 — 스토어 등록 전 확정 필요) |
| 패키지/번들 ID | `com.scorepoker.app` |
| 카테고리 | 게임 > 카드 |
| 콘텐츠 등급 | 전체이용가 (사행성 없음 — 베팅·현금화 요소 없음) |
| 개인정보처리방침 URL | https://parkfree771.github.io/score-poker/privacy.html |
| 인앱 상품 | `token_set_20` ₩4,990 / `token_shield_10` ₩3,300 / `token_attack_10` ₩3,300 — 전부 **소비성** |

## 한국어

**짧은 설명 (80자)**
포커 족보로 겨루는 1:1 전략 카드 배틀. 베팅 없이 순수 실력으로 3줄 중 2줄을 잡아라!

**전체 설명**

Score Poker는 베팅 없는 1:1 포커 스타일 전략 게임입니다.

각자 3줄 × 5칸의 필드에 카드를 배치해 줄마다 포커 족보로 승부하고,
3줄 중 2줄을 이기면 승리합니다.

■ 이런 게임입니다
- 운보다 전략: 매 턴 5장 손패에서 어느 줄에 무엇을 놓을지가 승부를 가릅니다
- 공격(빼앗기): 같은 숫자로 상대의 카드를 빼앗아 내 줄에 쉴드로 박습니다
- 조커: 단 2장뿐인 만능 카드 — 어떤 족보든 완성하고, 쉴드까지 깹니다
- 베팅 요소 없음: 돈을 걸지 않는 순수 실력 대결입니다

■ 싱글 플레이
기풍이 다른 3명의 상대(수비형·밸런스형·공격형)와 대전하고
전적과 랭킹 점수를 쌓아 티어를 올리세요.

■ 유료 아이템은 공정합니다
쉴드·공격 토큰은 한 판에 종류별 1개까지만 쓸 수 있습니다.
100개를 사도 한 판의 이득은 1개와 같습니다 — 승부는 실력으로 갈립니다.

## English

**Short description (80 chars)**
1v1 strategy card battle scored by poker hands. No betting — pure skill. Win 2 of 3 rows!

**Full description**

Score Poker is a 1v1 poker-style strategy game with no betting.

Place cards on your 3×5 field, battle row against row with poker hand
rankings, and win 2 out of 3 rows to take the match.

■ What makes it tick
- Strategy over luck: every turn, choosing where each of your 5 cards goes decides the game
- Attack (steal): match a rank to steal an opponent's card and lock it into your row as a shield
- Jokers: only 2 in the deck — complete any hand, and the only way to break shields
- No gambling: no bets, no cash-out, just skill

■ Single player
Face three AI opponents with distinct styles (defensive, balanced, aggressive),
build your record, and climb the ranked tiers.

■ Fair monetization
Shield and attack tokens are capped at 1 of each per match.
Buying 100 gives you exactly the same in-match advantage as using 1 — skill decides.

## 스크린샷 (등록 규격)

- Google Play: 휴대전화 스크린샷 최소 2장, 1080×1920 이상 권장. 태블릿 별도.
- App Store: 6.7" (1290×2796) 필수부터 시작.
- 구도 참고: `test/goldens/shot_*.png` (게임 보드·상점·결과·튜토리얼).
  실제 등록용은 기기/에뮬레이터 해상도로 다시 캡처할 것.

## Play Console 데이터 세이프티 답변지 (1.0 — 로그인 없음 기준)

> 로그인이 추가되면 이 답변지는 무효 — `docs/AUTH.md` §6에 따라 재작성할 것.

| 질문 | 답 |
|---|---|
| 앱이 필수 사용자 데이터를 수집하거나 공유하나요? | **아니요** |
| 데이터가 기기 외부로 전송되나요? | 아니요 (설정·기록·토큰 잔량 전부 기기 내 저장) |
| 결제 정보 | 수집 안 함 — 인앱 결제는 Google Play가 처리 (개발자는 접근 불가) |
| 광고 ID | 사용 안 함 (광고 없음) |
| 분석/크래시 SDK | 없음 |

콘텐츠 등급 설문 요점: 도박 요소 **없음**(실제/모의 화폐 베팅 없음 — 카드는 점수 대결 수단),
폭력 없음, 사용자 간 상호작용 없음(1.0은 싱글 전용) → 전체이용가 예상.

## 개인 개발자 계정 프로덕션 요건 (2023-11 이후 신규 계정)

프로덕션 공개 전 **비공개 테스트: 테스터 12명 이상이 연속 14일** 옵트인 상태 유지 필요.
- 테스터 모집: 지인 12명+ 의 Gmail 주소를 비공개 테스트 트랙에 등록
- 이 기간에 결제 테스트(라이선스 테스터 등록 → 테스트 카드 결제)와 밸런스 피드백을 같이 받는다
