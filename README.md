# Score Poker (작업용 코드네임)

1:1 포커 스타일 카드 배틀 게임. **베팅(사행성) 요소 없는** 순수 실력 대결.
Android + iOS 동시 출시 예정 (Flutter), 한국어/영어 지원.

## 게임 한 줄 요약
각자 3줄 × 5칸 필드에 카드를 올려 **포커 족보 순위**로 줄별 승부를 가리고, 3줄 중 2줄을 이기면 승리.
베팅 없이 랭킹/레이팅으로만 승부. 자세한 규칙: [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) (v1.0).

## 현재 상태
- [x] 게임 기획 문서 v1.0 (규칙 확정)
- [x] 한/영 i18n 셋업 (`lib/l10n/*.arb`)
- [x] 순수 Dart 도메인 로직: 카드/덱/족보 판정/줄·매치 점수 계산
- [x] **게임 규칙 엔진**(`domain/game.dart`): 셋업·선공·배치·제거·쉴드·조커·폴드·드로우·종료·정산
- [x] 단위 테스트 **42개 전부 통과**, `flutter analyze` 이슈 0
- [x] 앱 셸(홈 화면, 모드 선택)
- [x] **게임 보드/플레이 화면** (세로·가로 둘 다, 각 라인 상대줄/내줄 맞댐, 실시간 승패표시, 손패/배치/제거/쉴드/조커/폴드/결과)
- [x] web 지원 — 브라우저로 바로 실행 가능
- [ ] 싱글 AI (난이도 하/중/상)
- [ ] 온라인 매칭 + 랭킹 (백엔드/DB)

> 엔진의 애매한 규칙 기본값(쉴드 보상 방식, 드로우 시점 등)은 `lib/domain/game.dart` 상단 가정(A1~A6)에 명시. 검토/조정 가능.

## 프로젝트 구조
```
lib/
  main.dart            # 앱 진입점 + 로컬라이제이션 설정
  l10n/                # 한/영 번역 (app_en.arb=템플릿, app_ko.arb)
  domain/              # 순수 Dart 게임 로직 (Flutter 의존성 없음)
    card.dart          # Suit/Rank/PlayingCard, 덱 구성 정의
    deck.dart          # 58장 덱 생성/셔플/드로우
    hand.dart          # 포커 족보 판정 + 줄 숫자값(보너스) 계산
    scoring.dart       # 줄 비교 + 3줄 매치 승패 판정
  ui/
    home_screen.dart   # 메인 메뉴
test/                  # 도메인 로직 단위 테스트
docs/GAME_DESIGN.md    # 게임 기획 문서 (규칙 원본)
```

## 셋업 / 실행 (개발 환경)

> Flutter 3.44.4 / Dart 3.12.2 에서 빌드·테스트 검증됨. (web 빌드 OK, 테스트 46개 통과)

**브라우저로 바로 실행 (가장 쉬움, Android SDK 불필요):**
```
flutter pub get
flutter run -d chrome
```

**로직/위젯 테스트:**
```
flutter test          # 도메인+엔진+위젯 46개
flutter analyze
```

**안드로이드/iOS 빌드까지 하려면** 플랫폼 추가(이미 web은 추가됨):
```
flutter create . --platforms=android,ios --org com.example
flutter run           # 연결된 기기/에뮬레이터
```

## 설계 원칙 (유지보수 고려)
- **도메인 로직은 순수 Dart**로 UI/백엔드와 분리 → 테스트 쉽고, 나중에 백엔드(Firebase 등) 교체 자유.
- 모든 UI 문자열은 ARB 키로 관리 (하드코딩 금지).
- 온라인 랭킹/매칭은 백엔드+DB 필요. 싱글/로컬은 불필요. (MVP 백엔드 후보: Firebase)
