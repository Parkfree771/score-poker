import 'package:flutter_test/flutter_test.dart';

import 'package:score_poker/main.dart';
import 'package:score_poker/ui/home_screen.dart';

void main() {
  testWidgets('app launches to home screen', (tester) async {
    await tester.pumpWidget(const ScorePokerApp());
    // 홈 모드 카드의 로티가 무한 반복이라 pumpAndSettle은 끝나지 않는다 — 고정 펌프.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
