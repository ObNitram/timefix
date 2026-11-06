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

  @override
  Future<void> schedule(ReminderAlert alert, AlarmOptions options) async {
    scheduleCalls.add(alert.id);
    await super.schedule(alert, options);
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    cancelCalls.addAll(ids);
    await super.cancel(ids);
  }
}

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  final now = DateTime(2026, 11, 10, 8);
  late InMemoryCalendarRepository repo;
  late RecordingPlatform platform;
  late ReminderService service;
  var settings = ReminderSettings.defaults;

  setUp(() async {
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
    // 10 Nov 8:45 … 17 Nov 8:45 minus the past ones → 7 within 7 days.
    expect(platform.scheduled, hasLength(7));

    platform.maxPending = 3;
    await service.reschedule();
    expect(platform.scheduled, hasLength(3));

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
