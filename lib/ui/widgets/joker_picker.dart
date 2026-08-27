import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../domain/card.dart';
import '../../l10n/app_localizations.dart';
import '../theme.dart';
import 'card_face.dart';
import 'joker_card.dart';
import 'suit_glyphs.dart';

/// 조커를 어떤 카드로 만들지 고르는 시트. **숫자는 입력, 무늬는 선택.**
///
/// [strike]면 "상대 카드를 이 카드로 바꾼다"(붕괴), 아니면 "내 판에 이 카드로 놓는다"(와일드).
/// 고른 카드가 미리보기로 바로 그려진다. 확정하면 [PlayingCard]를, 닫으면 null을 돌려준다.
Future<PlayingCard?> showJokerPicker(BuildContext context,
    {required bool strike, PlayingCard? initial}) {
  return showModalBottomSheet<PlayingCard>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _JokerPickerSheet(strike: strike, initial: initial),
  );
}

class _JokerPickerSheet extends StatefulWidget {
  const _JokerPickerSheet({required this.strike, this.initial});
  final bool strike;
  final PlayingCard? initial;

  @override
  State<_JokerPickerSheet> createState() => _JokerPickerSheetState();
}

class _JokerPickerSheetState extends State<_JokerPickerSheet> {
  late final TextEditingController _rank =
      TextEditingController(text: widget.initial == null ? '' : '${widget.initial!.rank}');
  late Suit _suit = widget.initial?.suit ?? Suit.spades;

  int? get _rankValue {
    final t = _rank.text.trim().toUpperCase();
    final named = switch (t) {
      'J' => Ranks.jack,
      'Q' => Ranks.queen,
      'K' => Ranks.king,
      'A' => Ranks.ace,
      _ => int.tryParse(t),
    };
    if (named == null || named < Ranks.min || named > Ranks.max) return null;
    return named;
  }

  PlayingCard? get _card => _rankValue == null ? null : PlayingCard(_rankValue!, _suit);

  @override
  void dispose() {
    _rank.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final card = _card;
    final accent = widget.strike ? AppColors.red : JokerColors.gold;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: JokerColors.gold, width: 1.5)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const JokerBadge(size: 26, color: JokerColors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.strike ? l10n.jokerPickStrikeTitle : l10n.jokerPickWildTitle,
                        style: const TextStyle(
                            color: AppColors.textMain, fontSize: 17, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.strike ? l10n.jokerPickStrikeHint : l10n.jokerPickWildHint,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 미리보기 — 고르는 즉시 카드가 바뀐다.
                  SizedBox(
                    width: 84,
                    height: CardFace.heightFor(84),
                    child: card == null
                        ? const JokerFace(size: 84)
                        : CardFace(key: ValueKey(card.label), card: card, size: 84),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.jokerRankLabel,
                            style: const TextStyle(
                                color: AppColors.goldSoft, fontSize: 11.5, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        TextField(
                          key: const ValueKey('joker-rank'),
                          controller: _rank,
                          autofocus: true,
                          textCapitalization: TextCapitalization.characters,
                          keyboardType: const TextInputType.numberWithOptions(),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp('[0-9jqkaJQKA]')),
                            LengthLimitingTextInputFormatter(2),
                          ],
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                              color: AppColors.textMain, fontSize: 22, fontWeight: FontWeight.w900),
                          decoration: InputDecoration(
                            hintText: l10n.jokerRankHint,
                            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppColors.stroke),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: accent, width: 1.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final r in const ['J', 'Q', 'K', 'A'])
                              _Chip(
                                label: r,
                                selected: _rank.text.toUpperCase() == r,
                                onTap: () => setState(() => _rank.text = r),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(l10n.jokerSuitLabel,
                            style: const TextStyle(
                                color: AppColors.goldSoft, fontSize: 11.5, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (final s in Suit.values) ...[
                              _SuitButton(
                                suit: s,
                                selected: _suit == s,
                                onTap: () => setState(() => _suit = s),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton(
                key: const ValueKey('joker-confirm'),
                onPressed: card == null ? null : () => Navigator.of(context).pop(card),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  card == null
                      ? l10n.jokerPickNeedCard
                      : (widget.strike ? l10n.jokerConfirmStrike(card.label) : l10n.jokerConfirmWild(card.label)),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? JokerColors.gold : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? JokerColors.gold : AppColors.stroke),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? AppColors.ink : AppColors.textMain,
                fontWeight: FontWeight.w900,
                fontSize: 13)),
      ),
    );
  }
}

class _SuitButton extends StatelessWidget {
  const _SuitButton({required this.suit, required this.selected, required this.onTap});
  final Suit suit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('joker-suit-${suit.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0EAD6) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? JokerColors.gold : AppColors.stroke, width: selected ? 2 : 1),
        ),
        child: SvgPicture(suitLoader(suit), fit: BoxFit.contain),
      ),
    );
  }
}
