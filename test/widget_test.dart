import 'package:flutter_test/flutter_test.dart';

import 'package:score_poker/main.dart';
import 'package:score_poker/ui/home_screen.dart';

void main() {
  testWidgets('app launches to home screen', (tester) async {
    await tester.pumpWidget(const ScorePokerApp());
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
