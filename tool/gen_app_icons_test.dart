// 앱 아이콘 생성기 — 순수 Canvas로 그려서 모든 플랫폼 크기로 내보낸다.
//
// 실행: flutter test tool/gen_app_icons_test.dart
// 이후 iOS용 알파 제거: python tool/strip_icon_alpha.py
//
// 디자인: 그린 펠트 배경 + 아이보리 카드 2장(뒤 1장 살짝 비껴) + 웜 블랙 스페이드.
// 팔레트는 lib/ui/theme.dart(그린 펠트 & 브라스)와 동일.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// theme.dart와 동기화된 팔레트 (도구 파일이라 직접 상수로 둔다).
const _bgTop = Color(0xFF223B2F);
const _bgBottom = Color(0xFF14261D);
const _cardBody = Color(0xFFF5EFDF);
const _ink = Color(0xFF26251C);
const _dark = Color(0xFF2F2B24);
const _gold = Color(0xFFD4A24A);
const _goldDeep = Color(0xFF8A6B30);

void main() {
  testWidgets('generate app icons', (tester) async {
    await tester.runAsync(() async {
      // Android 레거시 런처 아이콘.
      const android = {
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
        'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
        'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
        'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
      };
      // iOS AppIcon.appiconset (Contents.json의 파일명 그대로).
      const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      const ios = {
        '$iosDir/Icon-App-20x20@1x.png': 20,
        '$iosDir/Icon-App-20x20@2x.png': 40,
        '$iosDir/Icon-App-20x20@3x.png': 60,
        '$iosDir/Icon-App-29x29@1x.png': 29,
        '$iosDir/Icon-App-29x29@2x.png': 58,
        '$iosDir/Icon-App-29x29@3x.png': 87,
        '$iosDir/Icon-App-40x40@1x.png': 40,
        '$iosDir/Icon-App-40x40@2x.png': 80,
        '$iosDir/Icon-App-40x40@3x.png': 120,
        '$iosDir/Icon-App-60x60@2x.png': 120,
        '$iosDir/Icon-App-60x60@3x.png': 180,
        '$iosDir/Icon-App-76x76@1x.png': 76,
        '$iosDir/Icon-App-76x76@2x.png': 152,
        '$iosDir/Icon-App-83.5x83.5@2x.png': 167,
        '$iosDir/Icon-App-1024x1024@1x.png': 1024,
      };
      const web = {
        'web/favicon.png': 32,
        'web/icons/Icon-192.png': 192,
        'web/icons/Icon-512.png': 512,
        'web/icons/Icon-maskable-192.png': 192,
        'web/icons/Icon-maskable-512.png': 512,
      };

      for (final e in {...android, ...ios, ...web}.entries) {
        // maskable은 가장자리 잘림을 견디도록 모티프를 중앙으로 모은다.
        final maskable = e.key.contains('maskable');
        final bytes = await _renderIcon(e.value, safeInset: maskable ? 0.10 : 0.0);
        File(e.key).writeAsBytesSync(bytes);
      }
      // 검수용 미리보기.
      File('build/icon_preview_1024.png').writeAsBytesSync(await _renderIcon(1024));
    });
  });
}

Future<List<int>> _renderIcon(int size, {double safeInset = 0.0}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();
  final rect = Rect.fromLTWH(0, 0, s, s);

  // ---- 배경: 펠트 그라데이션 + 중앙 광 ----
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_bgTop, _bgBottom],
      ).createShader(rect),
  );
  canvas.drawRect(
    rect,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.25),
        radius: 1.0,
        colors: [Colors.white.withValues(alpha: 0.10), Colors.transparent],
      ).createShader(rect),
  );

  // ---- 콘텐츠(카드+스페이드)는 중앙 기준, maskable이면 축소 ----
  canvas.save();
  canvas.translate(s / 2, s / 2);
  final k = (1.0 - safeInset * 2) * s / 1024.0; // 1024 기준 좌표계
  canvas.scale(k, k);

  void drawCard(double angleDeg, Color body, {bool withSpade = false}) {
    canvas.save();
    canvas.rotate(angleDeg * math.pi / 180);
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 560, height: 760),
      const Radius.circular(64),
    );
    canvas.drawRRect(
      cardRect.shift(const Offset(0, 22)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );
    canvas.drawRRect(cardRect, Paint()..color = body);
    canvas.drawRRect(
      cardRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gold, _goldDeep],
        ).createShader(cardRect.outerRect),
    );
    if (withSpade) {
      // 코너 인덱스(작은 스페이드) — 실물 카드 느낌.
      _drawSpade(canvas, center: const Offset(-212, -300), height: 96, color: _ink);
      _drawSpade(canvas, center: const Offset(212, 300), height: 96, color: _ink, flip: true);
      // 중앙 대형 스페이드.
      _drawSpade(canvas, center: const Offset(0, 10), height: 430, color: _dark, outline: _ink);
    }
    canvas.restore();
  }

  drawCard(9, const Color(0xFFE7DFC8)); // 뒤 카드(약간 어두운 아이보리)
  drawCard(-7, _cardBody, withSpade: true);

  canvas.restore();

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// 클래식 스페이드: 좌우 로브 + 위 꼭짓점 + 아래 꼬리. [height] 기준 비율 좌표.
void _drawSpade(
  Canvas canvas, {
  required Offset center,
  required double height,
  required Color color,
  Color? outline,
  bool flip = false,
}) {
  final path = Path();
  // 0..100 좌표계 (가로 100 = 세로 100, 실제 비율은 스케일로 조정).
  path.moveTo(50, 2);
  path.cubicTo(57, 20, 92, 34, 92, 60);
  path.cubicTo(92, 77, 79, 85, 67, 85);
  path.cubicTo(60, 85, 55, 81, 52.5, 75);
  path.cubicTo(52.5, 80, 54, 89, 59, 97);
  path.lineTo(41, 97);
  path.cubicTo(46, 89, 47.5, 80, 47.5, 75);
  path.cubicTo(45, 81, 40, 85, 33, 85);
  path.cubicTo(21, 85, 8, 77, 8, 60);
  path.cubicTo(8, 34, 43, 20, 50, 2);
  path.close();

  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (flip) canvas.rotate(math.pi);
  final scale = height / 100.0;
  canvas.scale(scale, scale);
  canvas.translate(-50, -50);
  canvas.drawPath(path, Paint()..color = color);
  if (outline != null) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..color = outline,
    );
  }
  canvas.restore();
}
