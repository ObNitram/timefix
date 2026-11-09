import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:timefix/data/event_service.dart';
import 'package:timefix/data/google/google_mapper.dart';
import 'package:timefix/data/ical/ical_service.dart';
import 'package:timefix/data/ical/ics_parser.dart';
import 'package:timefix/data/ical/ics_writer.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/domain/reminder_planner.dart';
import 'package:timefix/domain/reminders.dart';
import 'package:timefix/state/reminder_settings.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

CalendarEvent event({
  String id = 'e',
  DateTime? start,
  DateTime? end,
  bool allDay = false,
  List<Reminder> reminders = const [],
  String? recurringRemoteId,
}) {
  final s = start ?? DateTime(2026, 11, 10, 9);
  return CalendarEvent(
    id: id,
    calendarId: 'c',
    remoteId: 'uid-$id',
    title: 'Réunion',
    start: s,
    end: end ?? s.add(const Duration(hours: 1)),
    allDay: allDay,
    reminders: reminders,
    recurringRemoteId: recurringRemoteId,
  );
}

EventOccurrence occ(CalendarEvent e) =>
    EventOccurrence(event: e, start: e.start, end: e.end, color: Colors.blue);

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  group('model', () {
    test('all-day delays and parts round trip', () {
      for (final d in builtInAllDayDelays) {
        final p = allDayDelayParts(d);
        expect(allDayDelay(daysBefore: p.daysBefore, hour: p.hour, minute: p.minute), d);
      }
      expect(allDayDelayParts(-9 * 60), (daysBefore: 0, hour: 9, minute: 0));
      expect(allDayDelayParts(15 * 60), (daysBefore: 1, hour: 9, minute: 0));
      expect(allDayDelayParts(6 * 60), (daysBefore: 1, hour: 18, minute: 0));
    });

    test('fire times are wall-clock times (DST safe)', () {
      // Whatever the machine's time zone: day / hour fields, not durations.
      final allDayStart = DateTime(2026, 3, 30); // DST changed on 29 March in Europe
      expect(const Reminder(-9 * 60, ReminderType.push).fireTime(allDayStart, allDay: true),
          DateTime(2026, 3, 30, 9));
      expect(Reminder(allDayDelay(daysBefore: 2, hour: 9, minute: 0), ReminderType.push)
          .fireTime(allDayStart, allDay: true), DateTime(2026, 3, 28, 9));
      final timed = DateTime(2026, 10, 26, 8, 30);
      expect(const Reminder(24 * 60, ReminderType.push).fireTime(timed), DateTime(2026, 10, 25, 8, 30));
      expect(const Reminder(7 * 24 * 60, ReminderType.push).fireTime(timed), DateTime(2026, 10, 19, 8, 30));
      expect(const Reminder(24 * 60 + 30, ReminderType.push).fireTime(timed), DateTime(2026, 10, 25, 8));
      expect(const Reminder(15, ReminderType.push).fireTime(timed), DateTime(2026, 10, 26, 8, 15));
    });

    test('reminders under a day keep the instant (hour repeated when DST ends)', () {
      // In Europe/Paris 02:30 happens twice on 25 October 2026; the second
      // one is 01:30Z. Meaningful when run with TZ=Europe/Paris.
      final second = DateTime.utc(2026, 10, 25, 1, 30).toLocal();
      expect(const Reminder(10, ReminderType.push).fireTime(second).toUtc(), DateTime.utc(2026, 10, 25, 1, 20));
      expect(const Reminder(0, ReminderType.alarm).fireTime(second).toUtc(), DateTime.utc(2026, 10, 25, 1, 30));
    });

    test('switching all-day on or off converts the delays', () {
      expect(
          convertRemindersForAllDay(const [
            Reminder(10, ReminderType.push),
            Reminder(24 * 60, ReminderType.alarm),
            Reminder(-5, ReminderType.push),
          ], toAllDay: true),
          [
            Reminder(allDayDelay(daysBefore: 1, hour: 9, minute: 0), ReminderType.alarm),
            Reminder(allDayDelay(daysBefore: 0, hour: 9, minute: 0), ReminderType.push),
          ]);
      expect(
          convertRemindersForAllDay([
            Reminder(allDayDelay(daysBefore: 0, hour: 9, minute: 0), ReminderType.push),
            Reminder(allDayDelay(daysBefore: 2, hour: 18, minute: 0), ReminderType.fullScreen),
          ], toAllDay: false),
          const [Reminder(2 * 24 * 60, ReminderType.fullScreen), Reminder(0, ReminderType.push)]);
    });

    test('device-only reminders: occurrence entry, then series, then iCal master', () {
      final instance = event(id: 'c|inst1', recurringRemoteId: 'S');
      expect(deviceReminderKeys(instance), ['c|inst1', 'c|series|S']);
      final series = {'c|series|S': const [Reminder(10, ReminderType.alarm)]};
      expect(deviceReminders(instance, series), const [Reminder(10, ReminderType.alarm)]);
      // An explicit empty entry for this occurrence wins over the series.
      expect(deviceReminders(instance, {...series, 'c|inst1': const <Reminder>[]}), isEmpty);
      // A modified occurrence of an iCal series falls back to the series.
      final override = CalendarEvent(
          id: 'c|uid|123', calendarId: 'c', remoteId: 'uid', title: 'x',
          start: DateTime(2026, 11, 10), end: DateTime(2026, 11, 10, 1), recurrenceId: DateTime(2026, 11, 9));
      expect(deviceReminders(override, {'c|uid': const [Reminder(5, ReminderType.push)]}),
          const [Reminder(5, ReminderType.push)]);
    });

    test('normalize sorts earliest alert first and removes duplicates', () {
      final list = Reminder.normalize(const [
        Reminder(10, ReminderType.push),
        Reminder(60, ReminderType.alarm),
        Reminder(10, ReminderType.push),
        Reminder(10, ReminderType.alarm),
      ]);
      expect(list, const [
        Reminder(60, ReminderType.alarm),
        Reminder(10, ReminderType.push),
        Reminder(10, ReminderType.alarm),
      ]);
    });

    test('json and settings round trip', () {
      const list = [Reminder(15, ReminderType.fullScreen), Reminder(-540, ReminderType.alarm)];
      expect(Reminder.decodeList(Reminder.encodeList(list)), list);
      expect(Reminder.decodeList('not json'), isEmpty);
      final s = ReminderSettings.defaults.copyWith(snoozeMinutes: 5, alarmSound: 'digital');
      final back = ReminderSettings.fromJson(
          '{"presets":[{"id":"p","name":"Réveil","m":45,"t":"alarm","allDay":false}],'
          '"defaultTimed":[{"m":5,"t":"push"}],"defaultAllDay":[],"snoozeMinutes":5,'
          '"autoStopMinutes":2,"vibrate":false,"alarmSound":"digital"}');
      expect(back.presets.single.name, 'Réveil');
      expect(back.presets.single.reminder, const Reminder(45, ReminderType.alarm));
      expect((back.snoozeMinutes, back.autoStopMinutes, back.vibrate, back.alarmSound),
          (5, 2, false, s.alarmSound));
      expect(ReminderSettings.fromJson('{broken').presets, ReminderSettings.defaults.presets);
    });

    test('effective reminders merge device-only ones, Google series share a key', () {
      final instance = event(id: 'c|inst1', recurringRemoteId: 'series', reminders: const [
        Reminder(10, ReminderType.push),
      ]);
      expect(localReminderKey(instance), 'c|series|series');
      final merged = effectiveReminders(instance, {
        'c|series|series': const [Reminder(30, ReminderType.alarm)],
      });
      expect(merged, const [Reminder(30, ReminderType.alarm), Reminder(10, ReminderType.push)]);
    });
  });

  group('planner', () {
    final now = DateTime(2026, 11, 10, 8);

    test('keeps future alerts inside the horizon, earliest first, capped', () {
      final a = event(id: 'a', reminders: const [
        Reminder(0, ReminderType.push), // 09:00
        Reminder(30, ReminderType.alarm), // 08:30
        Reminder(120, ReminderType.push), // 07:00, already past
      ]);
      final b = event(id: 'b', start: DateTime(2026, 11, 20, 9), reminders: const [
        Reminder(10, ReminderType.fullScreen),
      ]);
      final planned = planReminders(
        occurrences: [occ(a), occ(b)],
        localReminders: const {},
        now: now,
        until: now.add(const Duration(days: 7)),
      );
      expect(planned.map((p) => (p.fireAt, p.type)), [
        (DateTime(2026, 11, 10, 8, 30), ReminderType.alarm),
        (DateTime(2026, 11, 10, 9), ReminderType.push),
      ]);
      final capped = planReminders(
          occurrences: [occ(a)], localReminders: const {}, now: now, until: DateTime(2027), maxCount: 1);
      expect(capped, hasLength(1));
    });

    test('alerts have stable distinct ids and signatures change with content', () {
      final e = event(reminders: const [Reminder(10, ReminderType.push), Reminder(10, ReminderType.alarm)]);
      final p1 = planReminders(occurrences: [occ(e)], localReminders: const {}, now: now, until: DateTime(2027));
      final p2 = planReminders(occurrences: [occ(e)], localReminders: const {}, now: now, until: DateTime(2027));
      expect(p1.map((p) => p.notificationId), p2.map((p) => p.notificationId));
      expect(p1.map((p) => p.notificationId).toSet(), hasLength(2));
      expect(p1.every((p) => p.notificationId > 0x1000 - 1 && p.notificationId < 0x80000000), isTrue);
      final renamed = e.copyWith(title: 'Autre titre');
      final p3 = planReminders(occurrences: [occ(renamed)], localReminders: const {}, now: now, until: DateTime(2027));
      expect(p3.first.notificationId, p1.first.notificationId);
      expect(p3.first.signature, isNot(p1.first.signature));
    });

    test('device-only reminders are planned too', () {
      final e = event();
      final planned = planReminders(
        occurrences: [occ(e)],
        localReminders: {'e': const [Reminder(5, ReminderType.alarm)]},
        now: now,
        until: DateTime(2027),
      );
      expect(planned.single.fireAt, DateTime(2026, 11, 10, 8, 55));
    });
  });

  group('iCalendar VALARM', () {
    test('round trip keeps delays and TimeFix types', () {
      final e = event(reminders: const [
        Reminder(1440, ReminderType.push),
        Reminder(90, ReminderType.fullScreen),
        Reminder(0, ReminderType.alarm),
      ]);
      final ics = IcsWriter.resource([e]);
      expect(ics, contains('TRIGGER:-P1D'));
      expect(ics, contains('TRIGGER:-PT90M'));
      expect(ics, contains('TRIGGER:PT0S'));
      expect(ics, contains('ACTION:AUDIO'));
      expect(ics, contains('X-TIMEFIX-REMINDER-TYPE:FULLSCREEN'));
      final back = IcalService.toEvents(IcsParser().parse(ics), 'c', includeReminders: true).single;
      expect(back.reminders, Reminder.normalize(e.reminders));
      // Read-only subscriptions ignore alarms.
      expect(IcalService.toEvents(IcsParser().parse(ics), 'c').single.reminders, isEmpty);
    });

    test('all-day "the same day at 9:00" is written after the start', () {
      final e = event(
          allDay: true,
          start: DateTime(2026, 11, 11),
          end: DateTime(2026, 11, 12),
          reminders: const [Reminder(-540, ReminderType.push)]);
      final ics = IcsWriter.resource([e]);
      expect(ics, contains('TRIGGER:PT9H'));
      final back = IcalService.toEvents(IcsParser().parse(ics), 'c', includeReminders: true).single;
      expect(back.reminders, const [Reminder(-540, ReminderType.push)]);
    });

    test('alarms TimeFix cannot model are kept verbatim', () {
      const ics = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\n'
          'DTSTART:20261110T090000Z\r\nDTEND:20261110T100000Z\r\nRRULE:FREQ=WEEKLY;COUNT=4\r\nSUMMARY:x\r\n'
          'BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nDESCRIPTION:x\r\nEND:VALARM\r\n'
          'BEGIN:VALARM\r\nACTION:EMAIL\r\nTRIGGER:-P1D\r\nSUMMARY:mail\r\nATTENDEE:mailto:a@b.c\r\nEND:VALARM\r\n'
          'BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER;VALUE=DATE-TIME:20261110T085000Z\r\nDESCRIPTION:once\r\nEND:VALARM\r\n'
          'BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-P6W\r\nDESCRIPTION:far\r\nEND:VALARM\r\n'
          'END:VEVENT\r\nEND:VCALENDAR\r\n';
      final e = IcalService.toEvents(IcsParser().parse(ics), 'c', includeReminders: true).single;
      expect(e.reminders, const [Reminder(15, ReminderType.push)]);
      expect(e.extraAlarms, hasLength(3));
      final out = IcsWriter.resource([e]);
      expect('BEGIN:VALARM'.allMatches(out), hasLength(4));
      expect(out, contains('ACTION:EMAIL'));
      expect(out, contains('ATTENDEE:mailto:a@b.c'));
      expect(out, contains('TRIGGER;VALUE=DATE-TIME:20261110T085000Z'));
      expect(out, contains('TRIGGER:-P6W'));
      // And they survive another round trip.
      final again = IcalService.toEvents(IcsParser().parse(out), 'c', includeReminders: true).single;
      expect(again.reminders, e.reminders);
      expect(again.extraAlarms, hasLength(3));
    });

    test('alarms written by other clients', () {
      const ics = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\n'
          'DTSTART:20261110T090000Z\r\nDTEND:20261110T100000Z\r\nSUMMARY:x\r\n'
          'BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER;RELATED=END:-PT30M\r\nDESCRIPTION:x\r\nEND:VALARM\r\n'
          'BEGIN:VALARM\r\nACTION:AUDIO\r\nTRIGGER;VALUE=DATE-TIME:20261110T083000Z\r\nEND:VALARM\r\n'
          'BEGIN:VALARM\r\nACTION:EMAIL\r\nTRIGGER:-PT1H\r\nEND:VALARM\r\n'
          'BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:no trigger\r\nEND:VALARM\r\n'
          'END:VEVENT\r\nEND:VCALENDAR\r\n';
      final e = IcalService.toEvents(IcsParser().parse(ics), 'c', includeReminders: true).single;
      // RELATED=END: 10:00 - 30 min = 09:30, i.e. 30 min after the start.
      expect(e.reminders, const [Reminder(30, ReminderType.push), Reminder(-30, ReminderType.push)]);
      expect(e.summaryForTest, 'x');
    });
  });

  group('Google', () {
    test('popup overrides and calendar defaults become notifications', () {
      final ge = gcal.Event()
        ..id = 'g1'
        ..summary = 'x'
        ..start = gcal.EventDateTime(dateTime: DateTime.utc(2026, 11, 10, 9))
        ..end = gcal.EventDateTime(dateTime: DateTime.utc(2026, 11, 10, 10))
        ..reminders = gcal.EventReminders(useDefault: false, overrides: [
          gcal.EventReminder(method: 'popup', minutes: 10),
          gcal.EventReminder(method: 'email', minutes: 60),
        ]);
      expect(GoogleMapper.fromGoogle(ge, 'c')!.reminders, const [Reminder(10, ReminderType.push)]);
      ge.reminders = gcal.EventReminders(useDefault: true);
      expect(
          GoogleMapper.fromGoogle(ge, 'c', calendarDefaults: const [Reminder(30, ReminderType.push)])!
              .reminders,
          const [Reminder(30, ReminderType.push)]);
      // The calendar defaults are those of timed events, not all-day ones.
      ge
        ..start = gcal.EventDateTime(date: DateTime(2026, 11, 11))
        ..end = gcal.EventDateTime(date: DateTime(2026, 11, 12));
      expect(
          GoogleMapper.fromGoogle(ge, 'c', calendarDefaults: const [Reminder(30, ReminderType.push)])!
              .reminders,
          isEmpty);
    });

    test('reminders are sent to Google only when asked, keeping useDefault', () {
      final e = event(reminders: const [Reminder(30, ReminderType.push), Reminder(5, ReminderType.alarm)]);
      expect(GoogleMapper.toGoogle(e, includeReminders: false).reminders, isNull);
      final withDefaults =
          GoogleMapper.toGoogle(e, calendarDefaults: const [Reminder(30, ReminderType.push)]).reminders!;
      expect(withDefaults.useDefault, isTrue);
      expect(GoogleMapper.sameGoogleReminders(
          const [Reminder(30, ReminderType.push), Reminder(5, ReminderType.alarm)],
          const [Reminder(30, ReminderType.push)]), isTrue);
    });

    test('only notifications Google can store are sent, the rest stays local', () {
      final split = EventService.splitGoogleReminders(const [
        Reminder(60, ReminderType.alarm),
        Reminder(30, ReminderType.push),
        Reminder(-540, ReminderType.push),
        Reminder(10, ReminderType.fullScreen),
      ]);
      expect(split.synced, const [Reminder(30, ReminderType.push)]);
      expect(split.local, const [
        Reminder(60, ReminderType.alarm),
        Reminder(10, ReminderType.fullScreen),
        Reminder(-540, ReminderType.push),
      ]);
      final g = GoogleMapper.toGoogle(event(reminders: const [
        Reminder(30, ReminderType.push),
        Reminder(60, ReminderType.alarm),
      ]));
      expect(g.reminders!.useDefault, isFalse);
      expect(g.reminders!.overrides!.map((o) => (o.method, o.minutes)), [('popup', 30)]);
    });
  });
}

extension on CalendarEvent {
  String get summaryForTest => title;
}
