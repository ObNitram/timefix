import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timefix/core/date_utils.dart';
import 'package:timefix/data/reminders/reminder_platform.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/domain/reminders.dart';
import 'package:timefix/ui/reminders/alarm_ring_screen.dart';

import '../helpers.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.localesTestValue = const [
      Locale('fr', 'FR'),
    ];
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  /// Lets the debounced rescheduling run.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('new events get the default reminder; an alarm can be added', (tester) async {
    await phone(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Nouvel événement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Train');
    expect(find.text('10 minutes avant'), findsOneWidget); // default reminder

    await tester.ensureVisible(find.text('Ajouter un rappel'));
    await tester.tap(find.text('Ajouter un rappel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alarme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 heure avant'));
    await tester.pumpAndSettle();
    expect(find.text('1 heure avant'), findsOneWidget);

    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    final saved = (await repo.searchEvents('Train', {'local:default'})).single;
    expect(saved.reminders, const [Reminder(60, ReminderType.alarm), Reminder(10, ReminderType.push)]);
  });

  testWidgets('reminders are scheduled and rescheduled after edits', (tester) async {
    await phone(tester);
    final repo = await seededRepository();
    final platform = FakeReminderPlatform();
    final start = DateTime.now().add(const Duration(hours: 3));
    await repo.upsertEvent(CalendarEvent(
      id: 'rem',
      calendarId: 'local:default',
      title: 'Médecin',
      start: start,
      end: start.add(const Duration(hours: 1)),
      reminders: const [Reminder(30, ReminderType.alarm), Reminder(10, ReminderType.fullScreen)],
    ));
    await tester.pumpWidget(await buildTestApp(repository: repo, reminders: platform));
    await settle(tester);
    var mine = platform.scheduled.values.where((a) => a.eventId == 'rem').toList();
    expect(mine.map((a) => a.type).toSet(), {ReminderType.alarm, ReminderType.fullScreen});
    expect(mine.first.title, 'Médecin');

    // Hiding the calendar removes its alerts.
    await tester.tap(find.byTooltip('Ouvrir le menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon calendrier'));
    await settle(tester);
    mine = platform.scheduled.values.where((a) => a.eventId == 'rem').toList();
    expect(mine, isEmpty);
  });

  testWidgets('tapping an alarm opens the ringing screen; snooze reschedules it', (tester) async {
    await phone(tester);
    final repo = await seededRepository();
    final platform = FakeReminderPlatform();
    await tester.pumpWidget(await buildTestApp(repository: repo, reminders: platform));
    await settle(tester);

    final now = DateTime.now();
    final alert = ReminderAlert(
      id: 4242,
      type: ReminderType.alarm,
      fireAt: now,
      title: 'Réveil vol',
      body: '',
      eventId: '1',
      start: now.add(const Duration(minutes: 30)),
      end: now.add(const Duration(minutes: 90)),
    );
    platform.respond(ReminderResponse(alert, ReminderAction.open));
    // The ringing screen animates forever: advance time step by step (it
    // closes itself after the auto-stop delay).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlarmRingScreen), findsOneWidget);
    expect(find.text('Réveil vol'), findsOneWidget);

    await tester.tap(find.text('Répéter (10 min)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlarmRingScreen), findsNothing);
    expect(platform.stopped, contains(4242));
    final snoozed = platform.scheduled.values.where((a) => a.title == 'Réveil vol').single;
    expect(snoozed.fireAt.difference(DateTime.now()).inMinutes, inInclusiveRange(9, 10));
  });

  testWidgets('the ringing screen stops by itself after the auto-stop delay', (tester) async {
    await phone(tester);
    final platform = FakeReminderPlatform();
    await tester.pumpWidget(await buildTestApp(repository: await seededRepository(), reminders: platform));
    await settle(tester);
    final now = DateTime.now();
    platform.respond(ReminderResponse(
        ReminderAlert(id: 7, type: ReminderType.alarm, fireAt: now, title: 'Auto', body: '',
            eventId: 'test', start: now, end: now),
        ReminderAction.open));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AlarmRingScreen), findsOneWidget);
    for (var i = 0; i < 5 * 60 + 2; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(AlarmRingScreen), findsNothing);
    expect(platform.stopped, [7]);
  });

  testWidgets('read-only events get device-only reminders from the details page', (tester) async {
    await phone(tester);
    final repo = await seededRepository();
    await repo.upsertSource(const CalendarSource(id: 'ical:x', type: SourceType.ical, name: 'Fériés'));
    await repo.upsertCalendar(const CalendarInfo(
        id: 'ical:x:main', sourceId: 'ical:x', name: 'Fériés', color: Colors.red, readOnly: true));
    final day = addDays(dateOnly(DateTime.now()), 1);
    await repo.upsertEvent(CalendarEvent(
        id: 'ical:x:main|ferie', calendarId: 'ical:x:main', title: 'Jour férié',
        start: day, end: addDays(day, 1), allDay: true));
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jour férié').first);
    await tester.pumpAndSettle();
    expect(find.text('Rappels enregistrés sur cet appareil uniquement.'), findsOneWidget);
    await tester.tap(find.text('Ajouter un rappel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('La veille à 09:00'));
    await tester.pumpAndSettle();
    expect(await repo.localReminders(), {
      'ical:x:main|ferie': const [Reminder(15 * 60, ReminderType.push)],
    });
    expect(find.text('La veille à 09:00'), findsOneWidget);
  });

  testWidgets('presets created in settings are offered in the editor', (tester) async {
    await phone(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ouvrir le menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rappels'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Nouveau preset'), 200);
    await tester.tap(find.text('Nouveau preset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Réveil sport');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Réveil sport'), findsOneWidget);

    // Back to the calendar, new event, the preset is in the picker.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Nouvel événement'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ajouter un rappel'));
    await tester.tap(find.text('Ajouter un rappel'));
    await tester.pumpAndSettle();
    // The sheet builds its rows lazily: scroll inside it.
    await tester.scrollUntilVisible(find.text('Réveil sport'), 150,
        scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réveil sport'));
    await tester.pumpAndSettle();
    expect(find.text('30 minutes avant'), findsOneWidget);
  });
}
