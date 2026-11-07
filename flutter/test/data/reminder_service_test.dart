import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timefix/data/calendar_repository.dart';
import 'package:timefix/data/reminders/notifications_reminder_platform.dart';
import 'package:timefix/data/reminders/reminder_platform.dart';
import 'package:timefix/data/reminders/reminder_service.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/domain/reminder_settings.dart';
import 'package:timefix/domain/reminders.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Records schedule / cancel calls.
class RecordingPlatform extends FakeReminderPlatform {
  final List<int> scheduleCalls = [];
  final List<int> cancelCalls = [];
  Duration delay = Duration.zero;

  @override
  Future<void> schedule(ReminderAlert alert, AlarmOptions options) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    scheduleCalls.add(alert.id);
    await super.schedule(alert, options);
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    cancelCalls.addAll(ids);
    await super.cancel(ids);
  }
}

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  var now = DateTime(2026, 11, 10, 8);
  late InMemoryCalendarRepository repo;
  late RecordingPlatform platform;
  late ReminderService service;
  var settings = ReminderSettings.defaults;

  ReminderService newService() => ReminderService(
        platform: platform,
        repository: repo,
        prefs: service.prefs,
        settings: () => settings,
        horizon: const Duration(days: 7),
        clock: () => now,
      );

  setUp(() async {
    now = DateTime(2026, 11, 10, 8);
    SharedPreferences.setMockInitialValues({});
    repo = InMemoryCalendarRepository();
    await repo.upsertSource(const CalendarSource(id: 's', type: SourceType.local, name: 'L'));
    await repo.upsertCalendar(const CalendarInfo(id: 'c', sourceId: 's', name: 'C', color: Colors.blue));
    platform = RecordingPlatform();
    settings = ReminderSettings.defaults;
    service = ReminderService(
      platform: platform,
      repository: repo,
      prefs: await SharedPreferences.getInstance(),
      settings: () => settings,
      horizon: const Duration(days: 7),
      clock: () => now,
    );
  });

  CalendarEvent event(String id, DateTime start, List<Reminder> reminders, {String? rrule}) => CalendarEvent(
        id: id,
        calendarId: 'c',
        title: 'Event $id',
        location: 'Salle B',
        start: start,
        end: start.add(const Duration(hours: 1)),
        reminders: reminders,
        rrule: rrule,
      );

  test('schedules alerts in the horizon with text, only once', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [
      Reminder(30, ReminderType.alarm),
      Reminder(10, ReminderType.push),
    ]));
    await repo.upsertEvent(event('far', DateTime(2026, 12, 25, 9), const [Reminder(10, ReminderType.push)]));
    await service.reschedule();
    expect(platform.scheduled, hasLength(2));
    final alarm = platform.scheduled.values.firstWhere((a) => a.type == ReminderType.alarm);
    expect(alarm.fireAt, DateTime(2026, 11, 10, 13, 30));
    expect(alarm.title, 'Event a');
    expect(alarm.body, contains('Salle B'));
    expect(service.upcomingRinging.single.id, alarm.id);

    // Nothing changed: nothing is scheduled again.
    platform.scheduleCalls.clear();
    await service.reschedule();
    expect(platform.scheduleCalls, isEmpty);
    expect(platform.cancelCalls, isEmpty);
  });

  test('changes cancel only the affected alerts', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [Reminder(10, ReminderType.push)]));
    await repo.upsertEvent(event('b', DateTime(2026, 11, 11, 14), const [Reminder(10, ReminderType.push)]));
    await service.reschedule();
    final idA = platform.scheduled.values.firstWhere((x) => x.eventId == 'a').id;
    final idB = platform.scheduled.values.firstWhere((x) => x.eventId == 'b').id;
    platform.scheduleCalls.clear();
    platform.cancelCalls.clear();

    // Rename a, delete b.
    await repo.upsertEvent((await repo.getEvent('a'))!.copyWith(title: 'Renamed'));
    await repo.deleteEvent('b');
    await service.reschedule();
    expect(platform.cancelCalls.toSet(), {idA, idB});
    expect(platform.scheduleCalls, [idA]);
    expect(platform.scheduled[idA]!.title, 'Renamed');
    expect(platform.scheduled.containsKey(idB), isFalse);
  });

  test('alarm settings changes reschedule alarms only', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [
      Reminder(30, ReminderType.alarm),
      Reminder(10, ReminderType.push),
    ]));
    await service.reschedule();
    platform.scheduleCalls.clear();
    settings = settings.copyWith(alarmSound: 'digital');
    await service.reschedule();
    expect(platform.scheduleCalls, hasLength(1));
    expect(platform.scheduled[platform.scheduleCalls.single]!.type, ReminderType.alarm);
  });

  test('recurring events, hidden calendars and the platform cap', () async {
    await repo.upsertEvent(event('daily', DateTime(2026, 11, 1, 9), const [Reminder(15, ReminderType.push)],
        rrule: 'FREQ=DAILY'));
    await service.reschedule();
    // 10 Nov 8:45 … 16 Nov 8:45 → 7 within 7 days, plus the "open the app"
    // sentinel because later occurrences are not scheduled yet.
    final daily = platform.scheduled.values.where((a) => a.eventId == 'daily').toList();
    expect(daily, hasLength(7));
    final sentinel = platform.scheduled[sentinelAlertId]!;
    expect(sentinel.fireAt, now.add(const Duration(days: 7)));

    platform.maxPending = 3;
    await service.reschedule();
    // 2 alerts + the sentinel right after the last one.
    expect(platform.scheduled.values.where((a) => a.eventId == 'daily'), hasLength(2));
    expect(platform.scheduled[sentinelAlertId]!.fireAt, DateTime(2026, 11, 11, 8, 46));

    await repo.upsertCalendar((await repo.getCalendar('c'))!.copyWith(visible: false));
    await service.reschedule();
    expect(platform.scheduled, isEmpty);
  });

  test('snooze and test alerts use their own ids and survive rescheduling', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [Reminder(30, ReminderType.alarm)]));
    await service.reschedule();
    final alert = platform.scheduled.values.single;
    final at = await service.snooze(alert);
    expect(at, now.add(const Duration(minutes: 10)));
    expect(platform.stopped, [alert.id]);
    expect(platform.scheduled, hasLength(2));
    await service.scheduleTest(ReminderType.fullScreen, locale: const Locale('fr'));
    expect(platform.scheduled[testAlertIds[ReminderType.fullScreen]]!.title, 'Test TimeFix');
    await service.reschedule();
    expect(platform.scheduled, hasLength(3));
    final snoozeId = platform.scheduled.keys.firstWhere((id) => id != alert.id && id != 102);
    expect(await service.isKnownAlert(snoozeId), isTrue);
    expect(service.upcomingRinging.map((a) => a.id), contains(snoozeId));

    // The event is deleted: its snooze is cancelled too.
    await repo.deleteEvent('a');
    await service.reschedule();
    expect(platform.scheduled.containsKey(snoozeId), isFalse);
  });

  test('alerts that already fired are never cancelled', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [
      Reminder(30, ReminderType.alarm),
      Reminder(0, ReminderType.push),
    ]));
    await service.reschedule();
    final alarmId = platform.scheduled.values.firstWhere((a) => a.type == ReminderType.alarm).id;
    platform.cancelCalls.clear();

    // 13:30:03: the alarm is ringing; the app opens and reschedules.
    now = DateTime(2026, 11, 10, 13, 30, 3);
    await service.reschedule();
    expect(platform.cancelCalls, isNot(contains(alarmId)));

    // Even when the event is then deleted, the ringing alarm is left alone
    // (only the still-pending push alert is cancelled).
    await repo.deleteEvent('a');
    await service.reschedule();
    expect(platform.cancelCalls, isNot(contains(alarmId)));
    expect(platform.cancelCalls, hasLength(1));
  });

  test('a new process schedules everything again (force-stop, restored backup)', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [Reminder(10, ReminderType.push)]));
    await service.reschedule();
    final scheduled = platform.scheduled.length;
    // The OS lost the alarms but the saved state says they exist.
    platform.scheduled.clear();
    platform.scheduleCalls.clear();
    await newService().reschedule();
    expect(platform.scheduled, hasLength(scheduled));
  });

  test('a new process leaves alerts alone when they are still scheduled', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [Reminder(10, ReminderType.push)]));
    await service.reschedule();
    platform.scheduleCalls.clear();
    await newService().reschedule();
    expect(platform.scheduleCalls, isEmpty);
  });

  test('a permission change schedules everything again', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [Reminder(30, ReminderType.alarm)]));
    await service.reschedule();
    platform.scheduleCalls.clear();
    await service.reschedule();
    expect(platform.scheduleCalls, isEmpty);
    platform.granted[ReminderPermission.alarmKit] = PermissionState.denied;
    await service.reschedule();
    expect(platform.scheduleCalls, hasLength(1));
  });

  test('rescheduleAll during a running reschedule loses nothing', () async {
    final slow = RecordingPlatform()..delay = const Duration(milliseconds: 5);
    final svc = ReminderService(
      platform: slow,
      repository: repo,
      prefs: service.prefs,
      settings: () => settings,
      horizon: const Duration(days: 7),
      clock: () => now,
    );
    for (var i = 0; i < 5; i++) {
      await repo.upsertEvent(event('e$i', DateTime(2026, 11, 11 + i, 9), const [
        Reminder(10, ReminderType.push),
        Reminder(30, ReminderType.alarm),
      ]));
    }
    await svc.reschedule();
    settings = settings.copyWith(alarmSound: 'gentle');
    final a = svc.reschedule();
    final b = svc.rescheduleAll();
    await Future.wait([a, b]);
    expect(slow.scheduled.values.where((x) => x.eventId.startsWith('e')), hasLength(10));
  });

  test('unknown ids are not trusted', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [Reminder(10, ReminderType.push)]));
    await service.reschedule();
    final id = platform.scheduled.values.first.id;
    expect(await service.isKnownAlert(id), isTrue);
    expect(await service.isKnownAlert(99999), isFalse);
    expect(await service.isKnownAlert(testAlertIds[ReminderType.alarm]!), isTrue);
  });

  test('delivered alerts stay known for a week after they fired', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [Reminder(10, ReminderType.push)]));
    await service.reschedule();
    final id = platform.scheduled.values.single.id;
    // Fired at 13:50; the app reschedules (resume, sync) before the tap.
    now = DateTime(2026, 11, 10, 13, 55);
    await service.reschedule();
    await newService().reschedule();
    expect(await service.isKnownAlert(id), isTrue);
    expect(platform.cancelCalls, isNot(contains(id)));
    // A week later it is forgotten.
    now = DateTime(2026, 11, 17, 14);
    await service.reschedule();
    expect(await service.isKnownAlert(id), isFalse);
  });

  test('snoozes made from a notification are tracked', () async {
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [Reminder(30, ReminderType.alarm)]));
    await service.reschedule();
    final alert = platform.scheduled.values.single;
    // "Snooze" tapped on the notification while the app was not running.
    final snoozed = alert.copyWith(id: 4242, fireAt: DateTime(2026, 11, 10, 13, 40));
    platform.scheduled[snoozed.id] = snoozed;
    platform.backgroundSnoozes.add(snoozed);
    expect(await service.isKnownAlert(4242), isTrue);
    await service.reschedule();
    expect(service.upcomingRinging.map((a) => a.id), contains(4242));
    // Its event is deleted: the snooze is cancelled with it.
    await repo.deleteEvent('a');
    await service.reschedule();
    expect(platform.scheduled.containsKey(4242), isFalse);
  });

  test('changes of the upcoming ringing alerts are notified', () async {
    var changes = 0;
    service.upcomingRingingListenable.addListener(() => changes++);
    await repo.upsertEvent(event('a', DateTime(2026, 11, 10, 14), const [Reminder(30, ReminderType.alarm)]));
    await service.reschedule();
    expect(changes, 1);
    await service.snooze(platform.scheduled.values.single);
    expect(changes, 2);
    await service.scheduleTest(ReminderType.alarm, locale: const Locale('en'));
    expect(changes, 3);
    expect(service.upcomingRinging.first.id, testAlertIds[ReminderType.alarm]);
    // A reschedule keeps the test alert that is still to come.
    await service.reschedule();
    expect(service.upcomingRinging.map((a) => a.id), contains(testAlertIds[ReminderType.alarm]));
  });

  test('device-only reminders are scheduled', () async {
    await repo.upsertEvent(event('ro', DateTime(2026, 11, 12, 9), const []));
    await repo.setLocalReminders('ro', const [Reminder(60, ReminderType.fullScreen)]);
    await service.reschedule();
    expect(platform.scheduled.values.single.fireAt, DateTime(2026, 11, 12, 8));
  });

  test('notification payload round trip keeps alert and options', () {
    final alert = ReminderAlert(
      id: 1234,
      type: ReminderType.alarm,
      fireAt: now,
      title: 'Vol',
      body: '10:00 – 11:00',
      eventId: 'ev',
      start: DateTime(2026, 11, 10, 10),
      end: DateTime(2026, 11, 10, 11),
      location: 'CDG',
    );
    const options = AlarmOptions(
      sound: 'gentle',
      vibrate: false,
      autoStop: Duration(minutes: 2),
      snooze: Duration(minutes: 15),
      snoozeLabel: 'Répéter (15 min)',
      channelAlarmName: 'Alarmes',
    );
    final payload = encodeReminderPayload(alert, options);
    expect(payload, startsWith('ring:'));
    final back = decodeReminderPayload(payload)!;
    expect((back.alert.id, back.alert.type, back.alert.title, back.alert.location, back.alert.start),
        (1234, ReminderType.alarm, 'Vol', 'CDG', DateTime(2026, 11, 10, 10)));
    expect((back.options.sound, back.options.vibrate, back.options.snooze, back.options.channelAlarmName),
        ('gentle', false, const Duration(minutes: 15), 'Alarmes'));
    expect(decodeReminderPayload('garbage'), isNull);
    expect(encodeReminderPayload(
        ReminderAlert(id: 1, type: ReminderType.push, fireAt: now, title: '', body: '', eventId: '',
            start: now, end: now),
        options), startsWith('rem:'));
  });
}
