# Score Poker (작업용 코드네임)

1:1 포커 스타일 카드 배틀 게임. **베팅(사행성) 요소 없는** 순수 실력 대결.
Android + iOS 동시 출시 예정 (Flutter), 한국어/영어 지원.

## 게임 한 줄 요약
각자 3줄 × 5칸 필드를 채우되 **카드는 뒷면으로 놓고 라운드마다 동시에 공개한다.**
같은 번호 줄끼리 포커 족보로 겨뤄 **3줄 중 2줄**을 이기면 승리. 판마다 주어지는
**비공개권 3개**로 내 카드를 숨기거나 상대가 숨긴 카드를 열어본다.
베팅 없이 랭킹/레이팅으로만 승부. 규칙 정본: [`docs/RULES.md`](docs/RULES.md) (v3.0).

## 현재 상태
- [x] 규칙 v3(**가림 룰**) 확정 — `docs/RULES.md`, 설계 근거는 `docs/GAME_DESIGN.md`
- [x] 한/영 i18n 셋업 (`lib/l10n/*.arb`) — 페르소나 대사까지 전부 번역을 거친다
- [x] 순수 Dart 도메인: 카드/덱(52장)/족보 판정/줄·매치 점수 계산
- [x] **규칙 엔진 v3**(`domain/game.dart`): 뒷면 배치 · 라운드 · 동시 공개 · 비공개권(숨기기/열어보기) · 최후 공개 · 정산
- [x] **페르소나 AI**(`domain/ai.dart`): 크로드(수비)·헷(공격)·제나(변칙)가 배치·숨김·열어보기 계수로 갈린다
- [x] 게임 화면(세로·가로): 딜링 연출 · 60초 타이머 · 봉인 도장 · 비공개권 코인 · 줄별 판정 세리머니 · 결과 오버레이
- [x] 단위/위젯 테스트 **163개 전부 통과**, `flutter analyze` 이슈 0
- [x] 홈·페르소나 선택·랭킹·설정·튜토리얼/규칙 화면, web 지원
- [x] 효과음(Kenney CC0 변환 + 자체 합성) · 햅틱 · 출시 준비(아이콘·서명·개인정보처리방침)
- [ ] 상점 상품 — 옛 토큰 상품은 규칙과 함께 내렸다. 새 규칙에 맞는 상품은 플레이 검증 후 설계(`docs/MONETIZATION.md`)
- [ ] 온라인 매칭 + 랭킹 (백엔드/DB — 설계는 `docs/PVP_SERVER.md`)

> **규칙 v3 요약** — 시작 손패 6장, 라운드마다 3장 보충 / 60초 안에 3장을 **뒷면으로** 배치
> (어느 줄에 놓는지는 상대에게 보인다) / 라운드 끝에 **동시 공개** / **비공개권 3개**로
> 숨기거나 상대의 지난 숨김을 열어본다 / 5라운드 후 최후 공개 → 3줄 2승 정산.
> 엔진 가정은 `lib/domain/game.dart` 상단(R1~R5)에 명시.

## 프로젝트 구조
```
lib/
  main.dart            # 앱 진입점 + 로컬라이제이션 설정
  l10n/                # 한/영 번역 (app_en.arb=템플릿, app_ko.arb)
  domain/              # 순수 Dart 게임 로직 (Flutter 의존성 없음)
    card.dart          # Suit/Rank/PlayingCard, 덱 구성 정의
    deck.dart          # 52장 덱 생성/셔플/드로우
    board.dart         # 판 공용 정의(PlayerId, 3줄×5칸)
    game.dart          # 규칙 엔진 v3(가림 룰)
    ai.dart            # 페르소나 기풍별 AI
    hand.dart          # 포커 족보 판정 + 줄 숫자값(보너스) 계산
    scoring.dart       # 줄 비교 + 3줄 매치 승패 판정
  ui/
    home_screen.dart   # 메인 메뉴
    game_screen.dart   # 게임 화면(딜링·타이머·공개 연출)
test/                  # 도메인 로직 단위 테스트
docs/RULES.md          # 규칙서(정본, 배포용)
docs/GAME_DESIGN.md    # 기획 문서(왜 그런 규칙인가)
```

## 셋업 / 실행 (개발 환경)

> Flutter 3.47.1 에서 빌드·테스트 검증됨. (web/AAB 빌드 OK, 테스트 163개 통과)

**브라우저로 바로 실행 (가장 쉬움, Android SDK 불필요):**
```
flutter pub get
flutter run -d chrome
```

**로직/위젯 테스트:**
```
flutter test          # 도메인+엔진+위젯+골든 193개
flutter analyze
```

**안드로이드/iOS 빌드까지 하려면** 플랫폼 추가(이미 web은 추가됨):
```
flutter create . --platforms=android,ios --org com.example
flutter run           # 연결된 기기/에뮬레이터
```

## 성능 (렉 방지 — 지키지 않으면 바로 프레임 예산 초과)

측정: `flutter test test/perf_bench_test.dart` (수치 출력) / 회귀 방지: `test/perf_regression_test.dart`

| 항목 | 개선 전 | 개선 후 |
|---|---|---|
| 게임화면 리빌드 (세로 430×930) | 26.4ms/frame | **8.7ms** |
| 게임화면 리빌드 (가로 1512×760) | 17.8ms/frame | **5.5ms** |

60fps 예산은 16.7ms/frame. 아래 세 가지가 핵심이다.

1. **`build()` 안에서 `GlobalKey()`를 만들지 말 것.** 키가 바뀌면 엘리먼트가 매 프레임
   파괴·재생성된다. 손패 키는 위치별 풀(`_handKey(i)`)에서 재사용한다.
2. **여러 장이 동시에 그려지는 카드는 `cachedCardFace`/`cachedCardBack`을 쓸 것.**
   Flutter는 `child.widget == newWidget`이면 서브트리 리빌드를 건너뛰는데, Widget의 `==`는
   `@nonVirtual`이라 재정의할 수 없으므로 **인스턴스를 재사용**해 같은 효과를 낸다.
3. **SVG는 `SvgPicture.string`이 아니라 캐시된 loader**(`suitLoader`/`cardFrameLoader` 등)를 쓸 것.
   색을 보간해 만드는 문자열이라 호출마다 새 loader가 생겨 디코드 캐시가 어긋난다.

## 설계 원칙 (유지보수 고려)

- **도메인은 사용자 문구를 갖지 않는다.** 규칙 위반은 `MoveError` enum으로 던지고,
  화면 문장은 `lib/ui/move_error_text.dart`에서 로케일에 맞춰 만든다.
  (예전엔 엔진이 한국어 문자열을 던지고 UI가 그대로 띄워서 영어 빌드에 한국어가 노출됐다)
- **도메인 로직은 순수 Dart**로 UI/백엔드와 분리 → 테스트 쉽고, 나중에 백엔드(Firebase 등) 교체 자유.
- 모든 UI 문자열은 ARB 키로 관리 (하드코딩 금지).
- 온라인 랭킹/매칭은 백엔드+DB 필요. 싱글/로컬은 불필요. (MVP 백엔드 후보: Firebase)
