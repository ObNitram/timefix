// Screenshot of the ringing screen (skipped unless SCREENSHOTS=true).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timefix/domain/reminders.dart';
import 'package:timefix/l10n/generated/app_localizations.dart';
import 'package:timefix/ui/reminders/alarm_ring_screen.dart';
import 'package:timefix/ui/theme.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

void main() {
  testWidgets('ring', (tester) async {
    final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
    Future<ByteData> load(String f) async => ByteData.sublistView(await File('$dir/$f').readAsBytes());
    await (FontLoader('Roboto')..addFont(load('Roboto-Regular.ttf'))..addFont(load('Roboto-Medium.ttf'))..addFont(load('Roboto-Light.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(load('MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final start = DateTime.now().add(const Duration(minutes: 60));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      locale: const Locale('fr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: AlarmRingScreen(
        reminder: RingingReminder(
          notificationId: 1,
          type: ReminderType.alarm,
          title: 'Vol pour Lyon',
          start: start,
          end: start.add(const Duration(hours: 1, minutes: 10)),
          allDay: false,
          location: 'Aéroport CDG, terminal 2',
        ),
        snoozeMinutes: 10,
        autoStop: const Duration(minutes: 5),
        onStop: () async {},
        onSnooze: () async {},
        onOpenEvent: () async {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 450));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../build/screenshots/ring.png'));
  }, skip: !_enabled);
}
