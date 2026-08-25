import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../audio/sfx.dart';
import '../data/app_settings.dart';
import '../feedback/haptics.dart';
import '../l10n/app_localizations.dart';
import 'how_to_play_screen.dart';
import 'rules_screen.dart';
import 'theme.dart';

/// 앱에서 고를 수 있는 언어.
///
/// **표시 이름은 번역하지 않는다.** 언어 목록은 그 언어를 쓰는 사람이 알아볼 수 있어야
/// 하므로, 한국어는 언제나 "한국어", 영어는 언제나 "English"로 보여준다.
/// (한국어 UI에서 "영어"라고 써 두면 영어 사용자가 자기 언어를 못 찾는다)
class LanguageOption {
  const LanguageOption(this.locale, this.nativeName);

  /// null이면 "시스템 설정 따름".
  final Locale? locale;
  final String nativeName;

  static const all = <LanguageOption>[
    LanguageOption(null, ''), // 시스템 — 이름은 l10n에서 가져온다
    LanguageOption(Locale('ko'), '한국어'),
    LanguageOption(Locale('en'), 'English'),
  ];
}

/// 설정: 언어 선택 + 효과음 + 앱 정보.
/// 스토어 등록에 쓴 것과 같은 주소(store/listing.md).
const kPrivacyPolicyUrl = 'https://parkfree771.github.io/score-poker/privacy.html';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.version = '1.0.0'});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = AppSettingsScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionLabel(l10n.languageSectionTitle),
                  const SizedBox(height: 8),
                  _Panel(
                    child: Column(
                      children: [
                        for (var i = 0; i < LanguageOption.all.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: AppColors.stroke),
                          _LanguageTile(
                            option: LanguageOption.all[i],
                            selected: settings.locale == LanguageOption.all[i].locale,
                            onTap: () => _select(context, LanguageOption.all[i].locale),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ..._soundSection(context, l10n),
                  _SectionLabel(l10n.howToPlayTitle),
                  const SizedBox(height: 8),
                  _Panel(
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                          leading: const Icon(Icons.school_rounded,
                              color: AppColors.gold, size: 20),
                          title: Text(l10n.howToPlayTitle,
                              style: const TextStyle(
                                  color: AppColors.textMain, fontWeight: FontWeight.w600)),
                          subtitle: Text(l10n.howToPlayDesc,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textMuted),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => const HowToPlayScreen()),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.stroke),
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                          leading: const Icon(Icons.menu_book_rounded,
                              color: AppColors.gold, size: 20),
                          title: Text(l10n.rulesTitle,
                              style: const TextStyle(
                                  color: AppColors.textMain, fontWeight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textMuted),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const RulesScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel(l10n.aboutSectionTitle),
                  const SizedBox(height: 8),
                  _Panel(
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                          title: Text(l10n.appVersion,
                              style: const TextStyle(
                                  color: AppColors.textMain, fontWeight: FontWeight.w600)),
                          trailing: Text(version,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                        ),
                        const Divider(height: 1, color: AppColors.stroke),
                        // 스토어 심사 필수 항목 — 앱 안에서 방침에 닿을 수 있어야 한다.
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                          leading: const Icon(Icons.privacy_tip_outlined,
                              color: AppColors.gold, size: 20),
                          title: Text(l10n.privacyPolicy,
                              style: const TextStyle(
                                  color: AppColors.textMain, fontWeight: FontWeight.w600)),
                          trailing: const Icon(Icons.open_in_new_rounded,
                              color: AppColors.textMuted, size: 18),
                          onTap: () => launchUrl(Uri.parse(kPrivacyPolicyUrl),
                              mode: LaunchMode.externalApplication),
                        ),
                        const Divider(height: 1, color: AppColors.stroke),
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                          leading: const Icon(Icons.article_outlined,
                              color: AppColors.gold, size: 20),
                          title: Text(l10n.openSourceLicenses,
                              style: const TextStyle(
                                  color: AppColors.textMain, fontWeight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textMuted),
                          onTap: () => showLicensePage(
                              context: context,
                              applicationName: l10n.appTitle,
                              applicationVersion: version),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 효과음·햅틱 on/off. 스코프가 없는 환경(위젯 테스트·스크린샷)에서는 섹션째 숨긴다.
  /// 햅틱 토글은 진동이 의미 있는 플랫폼(Android/iOS)에서만 보인다.
  List<Widget> _soundSection(BuildContext context, AppLocalizations l10n) {
    final sfx = SfxScope.maybeOf(context);
    if (sfx == null) return const [];
    final haptics = HapticScope.maybeOf(context);
    final showHaptics = haptics != null && haptics.supported;
    return [
      _SectionLabel(l10n.soundSectionTitle),
      const SizedBox(height: 8),
      _Panel(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              activeThumbColor: AppColors.gold,
              title: Text(l10n.soundEffectsTitle,
                  style: const TextStyle(
                      color: AppColors.textMain, fontWeight: FontWeight.w600)),
              subtitle: Text(l10n.soundEffectsDesc,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              value: sfx.enabled,
              onChanged: (v) => sfx.setEnabled(v),
            ),
            if (showHaptics) ...[
              const Divider(height: 1, color: AppColors.stroke),
              SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                activeThumbColor: AppColors.gold,
                title: Text(l10n.hapticsTitle,
                    style: const TextStyle(
                        color: AppColors.textMain, fontWeight: FontWeight.w600)),
                subtitle: Text(l10n.hapticsDesc,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                value: haptics.enabled,
                onChanged: (v) => haptics.setEnabled(v),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  Future<void> _select(BuildContext context, Locale? locale) async {
    final settings = AppSettingsScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await settings.setLocale(locale);
    if (!context.mounted) return;
    // 확인 문구는 **바뀐 언어로** 보여야 한다 — 지금 context가 이미 새 로케일이다.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).languageChanged)));
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.option, required this.selected, required this.onTap});

  final LanguageOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSystem = option.locale == null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      title: Text(
        isSystem ? l10n.languageSystem : option.nativeName,
        style: TextStyle(
          color: selected ? AppColors.gold : AppColors.textMain,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      subtitle: isSystem
          ? Text(l10n.languageSystemDesc,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12))
          : null,
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.gold, size: 22)
          : null,
      onTap: onTap,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  /// Container가 아니라 **Material**이어야 한다. ListTile은 가장 가까운 Material 위에
  /// 배경과 터치 잉크를 그리는데, 색칠된 Container를 끼우면 그 효과가 가려져
  /// **탭해도 아무 반응이 없는 것처럼 보인다.**
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.radius),
          side: const BorderSide(color: AppColors.stroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}
