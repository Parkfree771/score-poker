import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() => runApp(const ScorePokerApp());

class ScorePokerApp extends StatelessWidget {
  const ScorePokerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
