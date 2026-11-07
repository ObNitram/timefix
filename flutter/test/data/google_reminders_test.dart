import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:timefix/core/date_utils.dart';
import 'package:timefix/data/calendar_repository.dart';
import 'package:timefix/data/event_service.dart';
import 'package:timefix/data/ical/ical_service.dart';
import 'package:timefix/data/sync/sync_service.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/domain/occurrences.dart';
import 'package:timefix/domain/reminders.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../helpers.dart';

class FailingPatchGateway extends FakeGoogleGateway {
  bool failPatch = false;
  @override
  Future<gcal.Event> patchEvent(String calendarId, String eventId, gcal.Event event) {
    if (failPatch) throw Exception('offline');
    return super.patchEvent(calendarId, eventId, event);
  }
}

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  late InMemoryCalendarRepository repo;
  late FailingPatchGateway google;
  late SyncService sync;
  late EventService events;
  late CalendarInfo cal;
  const primary = 'me@example.com';

  gcal.Event gEvent(String id, int day, {String? series, List<gcal.EventReminder>? popups}) => gcal.Event()
    ..id = id
    ..summary = 'Event $id'
    ..recurringEventId = series
    ..start = gcal.EventDateTime(dateTime: DateTime.utc(2026, 11, day, 9))
    ..end = gcal.EventDateTime(dateTime: DateTime.utc(2026, 11, day, 10))
    ..reminders = gcal.EventReminders(useDefault: false, overrides: [
      ...?popups,
      gcal.EventReminder(method: 'email', minutes: 1440),
    ]);

  setUp(() async {
    repo = InMemoryCalendarRepository();
    google = FailingPatchGateway();
    google.calendars.add(gcal.CalendarListEntry()
      ..id = primary
      ..summary = 'Perso'
      ..accessRole = 'owner'
      ..defaultReminders = [gcal.EventReminder(method: 'popup', minutes: 30)]);
    google.events[primary] = [
      gEvent('g1', 10, popups: [gcal.EventReminder(method: 'popup', minutes: 10)]),
      gEvent('S_1', 11, series: 'S'),
      gEvent('S_2', 12, series: 'S'),
    ];
    sync = SyncService(repository: repo, ical: IcalService(), google: google);
    events = EventService(repository: repo, google: google, sync: sync);
    await sync.ensureLocalCalendar('Mon calendrier');
    await sync.addGoogleAccount();
    cal = (await repo.getCalendars()).firstWhere((c) => c.remoteId == primary);
  });

  Future<EventOccurrence> occ(String remoteId) async {
    final cals = {for (final c in await repo.getCalendars()) c.id: c};
    final range = DateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    return expandEvents(await repo.eventsForRange(range, cals.keys.toSet()), cals, range)
        .firstWhere((o) => o.event.remoteId == remoteId);
  }

  gcal.Event stored(String id) => google.events[primary]!.firstWhere((e) => e.id == id);

  test('editing the title does not touch Google reminders (e-mail ones survive)', () async {
    final o = await occ('g1');
    expect(o.event.reminders, const [Reminder(10, ReminderType.push)]);
    await events.update(original: o, edited: o.event.copyWith(title: 'Renamed'));
    expect(stored('g1').reminders, isNull, reason: 'PATCH without the reminders field');
  });

  test('changed reminders: popups to Google, alarms on the device after the patch', () async {
    final o = await occ('g1');
    const wanted = [Reminder(20, ReminderType.push), Reminder(60, ReminderType.alarm)];

    google.failPatch = true;
    await expectLater(events.update(original: o, edited: o.event.copyWith(reminders: wanted)), throwsException);
    expect(await repo.localReminders(), isEmpty, reason: 'nothing saved when the patch fails');

    google.failPatch = false;
    await events.update(original: o, edited: o.event.copyWith(reminders: wanted));
    expect(stored('g1').reminders!.overrides!.map((r) => (r.method, r.minutes)), [('popup', 20)]);
    expect(await repo.localReminders(), {o.event.id: const [Reminder(60, ReminderType.alarm)]});
  });

  test('popups equal to the calendar defaults keep useDefault', () async {
    final o = await occ('g1');
    await events.update(
        original: o, edited: o.event.copyWith(reminders: const [Reminder(30, ReminderType.push)]));
    expect(stored('g1').reminders!.useDefault, isTrue);
  });

  test('one occurrence of a series gets its own device-only reminders', () async {
    // Series-wide alarm, set e.g. from another occurrence.
    await repo.setLocalReminders('${cal.id}|series|S', const [Reminder(10, ReminderType.alarm)]);
    final first = await occ('S_1');
    expect(effectiveReminders(first.event, await repo.localReminders()), const [Reminder(10, ReminderType.alarm)]);

    // Remove the alarm on the 11th only.
    await events.update(original: first, edited: first.event.copyWith(reminders: const []));
    final local = await repo.localReminders();
    expect(effectiveReminders((await occ('S_1')).event, local), isEmpty);
    expect(effectiveReminders((await occ('S_2')).event, local), const [Reminder(10, ReminderType.alarm)]);
  });

  test('a single event that becomes recurring keeps its alarm for every instance', () async {
    final o = await occ('g1');
    await events.update(
        original: o,
        edited: o.event.copyWith(rrule: 'FREQ=WEEKLY', reminders: const [Reminder(30, ReminderType.alarm)]));
    final local = await repo.localReminders();
    expect(local['${cal.id}|series|g1'], const [Reminder(30, ReminderType.alarm)]);
    expect(local.containsKey(o.event.id), isFalse);
    // An instance Google would return later.
    final instance = o.event.copyWith(id: '${cal.id}|g1_20261117', recurringRemoteId: 'g1');
    expect(effectiveReminders(instance, local), contains(const Reminder(30, ReminderType.alarm)));
  });

  test('moving one occurrence to another calendar does not delete the series', () async {
    final o = await occ('S_1');
    await events.update(original: o, edited: o.event.copyWith(calendarId: 'local:default'));
    expect(google.events[primary]!.map((e) => e.id), containsAll(['g1', 'S_2']));
    expect(google.events[primary]!.map((e) => e.id), isNot(contains('S_1')));
  });
}
