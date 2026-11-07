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
    // Not scheduled by the service, but really displayed by the system.
    platform.displayed = {4242};
    platform.respond(ReminderResponse(alert, ReminderAction.open));
    // The ringing screen animates forever: advance time step by step (it
    // closes itself after the auto-stop delay).
    // The response is checked (asynchronously) before the screen opens.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('responses for unknown alerts are ignored (forged intents)', (tester) async {
    await phone(tester);
    final platform = FakeReminderPlatform()..displayed = {};
    await tester.pumpWidget(await buildTestApp(repository: await seededRepository(), reminders: platform));
    await settle(tester);
    final now = DateTime.now();
    final forged = ReminderAlert(id: 777, type: ReminderType.alarm, fireAt: now, title: 'Appelez le 0899…',
        body: '', eventId: 'x', start: now, end: now);
    platform.respond(ReminderResponse(forged, ReminderAction.open));
    platform.respond(ReminderResponse(forged, ReminderAction.snooze));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlarmRingScreen), findsNothing);
    expect(platform.scheduled.values.where((a) => a.title.startsWith('Appelez')), isEmpty);
  });

  testWidgets('the ringing screen closes when the alarm is stopped elsewhere', (tester) async {
    await phone(tester);
    final platform = FakeReminderPlatform()..displayed = {55};
    await tester.pumpWidget(await buildTestApp(repository: await seededRepository(), reminders: platform));
    await settle(tester);
    final now = DateTime.now();
    platform.respond(ReminderResponse(
        ReminderAlert(id: 55, type: ReminderType.alarm, fireAt: now, title: 'Ailleurs', body: '',
            eventId: 'test', start: now, end: now),
        ReminderAction.open));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AlarmRingScreen), findsOneWidget);
    expect(platform.enteredRing, 1);
    platform.displayed = {}; // stopped from the notification / watch
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AlarmRingScreen), findsNothing);
    expect(platform.leftRing, 1);
  });

  testWidgets('the ringing screen stops by itself after the auto-stop delay', (tester) async {
    await phone(tester);
    final platform = FakeReminderPlatform();
    await tester.pumpWidget(await buildTestApp(repository: await seededRepository(), reminders: platform));
    await settle(tester);
    final now = DateTime.now();
    platform.displayed = {7};
    platform.respond(ReminderResponse(
        ReminderAlert(id: 7, type: ReminderType.alarm, fireAt: now, title: 'Auto', body: '',
            eventId: 'test', start: now, end: now),
        ReminderAction.open));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
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

  ReminderAlert ringing(int id, String title, {ReminderType type = ReminderType.alarm}) {
    final now = DateTime.now();
    return ReminderAlert(
        id: id, type: type, fireAt: now, title: title, body: '', eventId: 'test', start: now, end: now);
  }

  Future<void> showRing(WidgetTester tester, FakeReminderPlatform platform, ReminderAlert alert) async {
    platform.respond(ReminderResponse(alert, ReminderAction.open));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a ringing screen below another one closes without closing it', (tester) async {
    await phone(tester);
    final platform = FakeReminderPlatform()..displayed = {61, 62};
    await tester.pumpWidget(await buildTestApp(repository: await seededRepository(), reminders: platform));
    await settle(tester);
    await showRing(tester, platform, ringing(61, 'Premier'));
    await showRing(tester, platform, ringing(62, 'Second'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AlarmRingScreen, skipOffstage: false), findsNWidgets(2));

    // The first alarm is stopped from the notification shade.
    platform.displayed = {62};
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlarmRingScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(platform.leftRing, 0, reason: 'still ringing on screen');

    await tester.tap(find.text('Arrêter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlarmRingScreen), findsNothing);
    expect(platform.stopped, [62]);
    expect(platform.leftRing, 1);
  });

  testWidgets('a tap delivered while the app is in use does not send it to the background', (tester) async {
    await phone(tester);
    final platform = FakeReminderPlatform()..displayed = {71};
    await tester.pumpWidget(await buildTestApp(repository: await seededRepository(), reminders: platform));
    await settle(tester);
    // Android pauses the activity ("inactive") to deliver the tap.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await showRing(tester, platform, ringing(71, 'Heads-up'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.tap(find.text('Arrêter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(platform.leftRingBackground, [false]);
  });

  testWidgets('test alarms ring on screen while the app is open', (tester) async {
    await phone(tester);
    final platform = FakeReminderPlatform();
    await tester.pumpWidget(await buildTestApp(repository: await seededRepository(), reminders: platform));
    await settle(tester);
    await tester.tap(find.byTooltip('Ouvrir le menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rappels'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text("Tester l'alarme"), 200);
    await tester.ensureVisible(find.text("Tester l'alarme"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Tester l'alarme"));
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(AlarmRingScreen), findsOneWidget);
    await tester.tap(find.text('Arrêter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('a denied permission is asked once; the settings open only from "Autoriser"', (tester) async {
    await phone(tester);
    final repo = await seededRepository();
    final platform = FakeReminderPlatform()
      ..granted[ReminderPermission.notifications] = PermissionState.denied
      ..grantOnRequest = false;
    await tester.pumpWidget(await buildTestApp(repository: repo, reminders: platform));
    await settle(tester);

    Future<void> createEvent(String title) async {
      await tester.tap(find.byTooltip('Nouvel événement'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, title);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
    }

    await createEvent('Un'); // with the default "10 minutes before"
    expect(platform.requests, [(ReminderPermission.notifications, false)]);
    expect(find.text('Autorisez les notifications pour recevoir vos rappels.'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await createEvent('Deux');
    expect(platform.requests, hasLength(1), reason: 'no second system dialog');
    await tester.tap(find.text('Autoriser'));
    await tester.pumpAndSettle();
    expect(platform.requests.last, (ReminderPermission.notifications, true));
    expect((await repo.searchEvents('Deux', {'local:default'})), hasLength(1));
  });

  testWidgets('switching an event to all-day converts its reminders, and back', (tester) async {
    await phone(tester);
    final repo = await seededRepository();
    final start = DateTime.now().add(const Duration(days: 1));
    await repo.upsertEvent(CalendarEvent(
      id: 'conv',
      calendarId: 'local:default',
      title: 'Conversion',
      start: start,
      end: start.add(const Duration(hours: 1)),
      reminders: const [Reminder(10, ReminderType.push)],
    ));
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conversion').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    expect(find.text('10 minutes avant'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Le jour même à 09:00'), findsOneWidget);
    expect(find.text('10 minutes avant'), findsNothing);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('10 minutes avant'), findsOneWidget);
  });

  testWidgets('a moved occurrence shows and edits the series device reminders', (tester) async {
    await phone(tester);
    final repo = await seededRepository();
    await repo.upsertSource(const CalendarSource(id: 'ical:x', type: SourceType.ical, name: 'Cours'));
    await repo.upsertCalendar(const CalendarInfo(
        id: 'ical:x:main', sourceId: 'ical:x', name: 'Cours', color: Colors.teal, readOnly: true));
    final day = addDays(dateOnly(DateTime.now()), 1);
    final moved = DateTime(day.year, day.month, day.day, 14);
    await repo.upsertEvent(CalendarEvent(
        id: 'ical:x:main|u1|moved', calendarId: 'ical:x:main', remoteId: 'u1', title: 'Cours déplacé',
        start: moved, end: moved.add(const Duration(hours: 1)), recurrenceId: DateTime(day.year, day.month, day.day, 10)));
    // Alarm set for the whole series.
    await repo.setLocalReminders('ical:x:main|u1', const [Reminder(45, ReminderType.alarm)]);
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cours déplacé').first);
    await tester.pumpAndSettle();
    expect(find.text('45 minutes avant'), findsOneWidget);

    // Removed for this occurrence only: an explicit empty entry.
    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Appliquer les rappels de cet appareil à'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await repo.localReminders(), {
      'ical:x:main|u1': const [Reminder(45, ReminderType.alarm)],
      'ical:x:main|u1|moved': const <Reminder>[],
    });
    expect(find.text('45 minutes avant'), findsNothing);
  });
}
