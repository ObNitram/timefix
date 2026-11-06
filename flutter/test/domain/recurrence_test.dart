import 'package:flutter_test/flutter_test.dart';
import 'package:timefix/core/date_utils.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/domain/recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  const expander = RecurrenceExpander();

  CalendarEvent event({
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String? rrule,
    List<DateTime> exdates = const [],
    String? timeZone,
  }) =>
      CalendarEvent(
        id: 'e',
        calendarId: 'c',
        title: 'Test',
        start: start,
        end: end,
        allDay: allDay,
        rrule: rrule,
        exdates: exdates,
        timeZone: timeZone,
      );

  test('non recurring event overlapping the range', () {
    final e = event(start: DateTime(2026, 11, 6, 10), end: DateTime(2026, 11, 6, 11));
    expect(expander.occurrences(e, dayRange(DateTime(2026, 11, 6))), hasLength(1));
    expect(expander.occurrences(e, dayRange(DateTime(2026, 11, 7))), isEmpty);
  });

  test('weekly rule with BYDAY and exdate', () {
    final e = event(
      start: DateTime(2026, 11, 2, 9),
      end: DateTime(2026, 11, 2, 10),
      rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
      exdates: [DateTime(2026, 11, 4, 9)],
    );
    final occ = expander.occurrences(
        e, DateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 15)));
    expect(occ.map((o) => o.$1).toList(), [
      DateTime(2026, 11, 2, 9),
      DateTime(2026, 11, 9, 9),
      DateTime(2026, 11, 11, 9),
    ]);
    expect(occ.first.$2, DateTime(2026, 11, 2, 10));
  });

  test('COUNT and UNTIL limit the series', () {
    final counted = event(
        start: DateTime(2026, 1, 1, 8),
        end: DateTime(2026, 1, 1, 9),
        rrule: 'FREQ=DAILY;COUNT=3');
    expect(
        expander.occurrences(counted, DateRange(DateTime(2026), DateTime(2027))),
        hasLength(3));

    final until = event(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 2),
        allDay: true,
        rrule: 'FREQ=DAILY;UNTIL=20260105');
    expect(expander.occurrences(until, DateRange(DateTime(2026), DateTime(2027))),
        hasLength(5));
  });

  test('monthly all-day events far after the start', () {
    final e = event(
        start: DateTime(2020, 3, 15),
        end: DateTime(2020, 3, 16),
        allDay: true,
        rrule: 'FREQ=MONTHLY;BYMONTHDAY=15');
    final occ = expander.occurrences(
        e, DateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1)));
    expect(occ, [(DateTime(2026, 11, 15), DateTime(2026, 11, 16))]);
  });

  test('wall-clock time is kept across DST in the event time zone', () {
    final paris = tz.getLocation('Europe/Paris');
    // 9:00 Paris time on Monday 19 Oct 2026 (UTC+2) → 26 Oct (UTC+1)
    final start = tz.TZDateTime(paris, 2026, 10, 19, 9).toLocal();
    final e = event(
      start: start,
      end: start.add(const Duration(hours: 1)),
      rrule: 'FREQ=WEEKLY',
      timeZone: 'Europe/Paris',
    );
    final occ = expander.occurrences(
        e, DateRange(DateTime(2026, 10, 18), DateTime(2026, 11, 1)));
    expect(occ, hasLength(2));
    final hoursParis =
        occ.map((o) => tz.TZDateTime.from(o.$1, paris).hour).toList();
    expect(hoursParis, [9, 9]);
    expect(occ[1].$1.toUtc().hour, 8); // UTC+1 after the change
  });

  test('long event starting before the range is returned', () {
    final e = event(
        start: DateTime(2026, 11, 1, 20),
        end: DateTime(2026, 11, 3, 8),
        rrule: 'FREQ=WEEKLY');
    final occ = expander.occurrences(e, dayRange(DateTime(2026, 11, 2)));
    expect(occ, hasLength(1));
  });

  test('presets round trip', () {
    final d = DateTime(2026, 11, 6); // Friday
    for (final p in RecurrencePreset.values) {
      if (p == RecurrencePreset.none || p == RecurrencePreset.custom) continue;
      expect(presetForRrule(rruleForPreset(p, d)), p, reason: p.name);
    }
    expect(presetForRrule('FREQ=WEEKLY;INTERVAL=2'), RecurrencePreset.custom);
    expect(presetForRrule(null), RecurrencePreset.none);
  });

  test('rruleEndingBefore stops the series before an occurrence', () {
    final e = event(
        start: DateTime(2026, 11, 1, 9),
        end: DateTime(2026, 11, 1, 10),
        rrule: 'FREQ=DAILY;COUNT=30');
    final cut = rruleEndingBefore(e.rrule!, DateTime(2026, 11, 5, 9), false);
    expect(cut, isNot(contains('COUNT')));
    final occ = expander.occurrences(e.copyWith(rrule: cut),
        DateRange(DateTime(2026, 10, 1), DateTime(2026, 12, 31)));
    expect(occ.map((o) => o.$1.day), [1, 2, 3, 4]);

    final allDay = event(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 2),
        allDay: true,
        rrule: 'FREQ=DAILY');
    final cut2 = rruleEndingBefore(allDay.rrule!, DateTime(2026, 11, 3), true);
    expect(
        expander
            .occurrences(allDay.copyWith(rrule: cut2),
                DateRange(DateTime(2026, 10, 1), DateTime(2026, 12, 31)))
            .length,
        2);
  });

  test('invalid rule falls back to a single occurrence', () {
    final e = event(
        start: DateTime(2026, 11, 6, 10),
        end: DateTime(2026, 11, 6, 11),
        rrule: 'FREQ=NONSENSE');
    expect(expander.occurrences(e, dayRange(DateTime(2026, 11, 6))), hasLength(1));
  });
}
