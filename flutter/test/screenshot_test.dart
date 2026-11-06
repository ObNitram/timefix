// Renders the main screens to PNG files (in build/screenshots/), with the
// real Roboto and Material Icons fonts. Skipped by default; run with:
//   flutter test test/screenshot_test.dart --update-goldens --dart-define=SCREENSHOTS=true
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timefix/state/settings.dart';

import 'helpers.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> load(String f) async =>
      ByteData.sublistView(await File('$dir/$f').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(load('Roboto-Regular.ttf'))
    ..addFont(load('Roboto-Medium.ttf'))
    ..addFont(load('Roboto-Bold.ttf'));
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(load('MaterialIcons-Regular.otf'))).load();
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    CalendarViewMode view = CalendarViewMode.schedule,
    Brightness brightness = Brightness.light,
    Future<void> Function()? before,
  }) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(
      repository: repo,
      prefs: {'viewMode': view.index},
    ));
    await tester.pumpAndSettle();
    if (before != null) await before();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/screenshots/$name.png'),
    );
  }

  testWidgets('schedule', (t) => shoot(t, 'schedule'), skip: !_enabled);
  testWidgets('week', (t) => shoot(t, 'week', view: CalendarViewMode.week), skip: !_enabled);
  testWidgets('month', (t) => shoot(t, 'month', view: CalendarViewMode.month), skip: !_enabled);
  testWidgets('month_dark',
      (t) => shoot(t, 'month_dark', view: CalendarViewMode.month, brightness: Brightness.dark),
      skip: !_enabled);
  testWidgets('drawer', (t) async {
    await shoot(t, 'drawer', before: () async {
      await t.tap(find.byTooltip('Ouvrir le menu'));
      await t.pumpAndSettle();
    });
  }, skip: !_enabled);
  testWidgets('mini_calendar', (t) async {
    await shoot(t, 'mini_calendar', view: CalendarViewMode.week, before: () async {
      await t.tap(find.byIcon(Icons.arrow_drop_down));
      await t.pumpAndSettle();
    });
  }, skip: !_enabled);
  testWidgets('details', (t) async {
    await shoot(t, 'details', before: () async {
      await t.tap(find.text('Réunion d\'équipe'));
      await t.pumpAndSettle();
    });
  }, skip: !_enabled);
  testWidgets('editor', (t) async {
    await shoot(t, 'editor', before: () async {
      await t.tap(find.text('Course à pied').first);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Modifier'));
      await t.pumpAndSettle();
    });
  }, skip: !_enabled);
  testWidgets('add_calendar', (t) async {
    await shoot(t, 'add_calendar', before: () async {
      await t.tap(find.byTooltip('Ouvrir le menu'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ajouter un calendrier'));
      await t.pumpAndSettle();
    });
  }, skip: !_enabled);
}
