import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timefix/core/date_utils.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/domain/recurrence.dart';
import 'package:timefix/domain/series_edit.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // 2 November 2026 is a Monday.
  final monday = DateTime(2026, 11, 2, 9);
  final tuesday = DateTime(2026, 11, 3, 9);

  CalendarEvent series(String rule, {DateTime? start, List<DateTime> exdates = const []}) {
    final s = start ?? monday;
    return CalendarEvent(
        id: 's', calendarId: 'c', title: 'Gym', start: s, end: s.add(const Duration(hours: 1)),
        rrule: rule, exdates: exdates);
  }

  List<DateTime> starts(CalendarEvent e, DateTime from, DateTime to) =>
      [for (final o in const RecurrenceExpander().occurrences(e, DateRange(from, to))) o.$1];

  group('rruleMovedBy', () {
    test('weekly day follows the move', () {
      expect(rruleMovedBy('FREQ=WEEKLY;BYDAY=MO', monday, tuesday), 'FREQ=WEEKLY;BYDAY=TU');
      expect(rruleMovedBy('FREQ=WEEKLY;BYDAY=MO,WE', monday, tuesday), 'FREQ=WEEKLY;BYDAY=TU,WE');
      // The new day is already in the rule: left as it is.
      expect(rruleMovedBy('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', monday, tuesday),
          'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR');
      // Same day, other time: nothing to change.
      expect(rruleMovedBy('FREQ=WEEKLY;BYDAY=MO', monday, DateTime(2026, 11, 2, 18)), 'FREQ=WEEKLY;BYDAY=MO');
    });

    test('monthly day of month and position follow the move', () {
      expect(rruleMovedBy('FREQ=MONTHLY;BYMONTHDAY=15', DateTime(2026, 11, 15), DateTime(2026, 11, 16)),
          'FREQ=MONTHLY;BYMONTHDAY=16');
      // 2nd Tuesday (10 Nov) moved to Wednesday 18 Nov: 3rd Wednesday.
      expect(rruleMovedBy('FREQ=MONTHLY;BYDAY=2TU', DateTime(2026, 11, 10), DateTime(2026, 11, 18)),
          'FREQ=MONTHLY;BYDAY=3WE');
      // Last Friday (27 Nov) moved to Thursday 26: last Thursday.
      expect(rruleMovedBy('FREQ=MONTHLY;BYDAY=-1FR', DateTime(2026, 11, 27), DateTime(2026, 11, 26)),
          'FREQ=MONTHLY;BYDAY=-1TH');
      expect(rruleMovedBy('FREQ=YEARLY;BYMONTH=11;BYMONTHDAY=2;COUNT=3', monday, DateTime(2026, 12, 5)),
          'FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=5;COUNT=3');
    });
  });

  test('"all": a weekly series moved from Monday to Tuesday repeats on Tuesdays', () {
    final master = series('FREQ=WEEKLY;BYDAY=MO', exdates: [DateTime(2026, 11, 16, 9)]);
    // The third occurrence (16 Nov is excluded, so 23 Nov) is moved to Tuesday 10:00.
    final edited = master.copyWith(start: DateTime(2026, 11, 24, 10), end: DateTime(2026, 11, 24, 11));
    final moved = wholeSeries(master, DateTime(2026, 11, 23, 9), edited);
    expect(moved.rrule, 'FREQ=WEEKLY;BYDAY=TU');
    expect(moved.start, DateTime(2026, 11, 3, 10));
    expect(moved.exdates, [DateTime(2026, 11, 17, 10)]);
    expect(starts(moved, DateTime(2026, 11, 1), DateTime(2026, 12, 1)), [
      DateTime(2026, 11, 3, 10),
      DateTime(2026, 11, 10, 10),
      DateTime(2026, 11, 24, 10),
    ]);
  });

  test('"this and following" keeps the remaining COUNT and later excluded dates', () {
    final master = series('FREQ=DAILY;COUNT=10', exdates: [DateTime(2026, 11, 4, 9), DateTime(2026, 11, 9, 9)]);
    final sixth = DateTime(2026, 11, 7, 9);
    final following = followingSeries(master, sixth, master.copyWith(title: 'Daily', start: sixth,
        end: sixth.add(const Duration(hours: 1))));
    expect(following.rrule, 'FREQ=DAILY;COUNT=5');
    expect(following.exdates, [DateTime(2026, 11, 9, 9)]);
    // A rule chosen by the user is kept as it is.
    final changed = followingSeries(master, sixth,
        master.copyWith(start: sixth, end: sixth.add(const Duration(hours: 1)), rrule: 'FREQ=WEEKLY'));
    expect(changed.rrule, 'FREQ=WEEKLY');
    expect(changed.exdates, isEmpty);
  });

  test('moves keep the wall-clock time across DST', () {
    // Moved by one hour on the day of an occurrence after a DST change.
    final shifted = shiftLikeMove(DateTime(2026, 3, 2, 9), DateTime(2026, 4, 6, 9), DateTime(2026, 4, 6, 10));
    expect(shifted, DateTime(2026, 3, 2, 10));
    expect(shiftLikeMove(DateTime(2026, 3, 2), DateTime(2026, 4, 6), DateTime(2026, 4, 8), allDay: true),
        DateTime(2026, 3, 4));
  });

  test('copyWith(clearRemote) drops only the link to the remote copy', () {
    final e = series('FREQ=DAILY').copyWith(
        remoteId: 'uid', href: '/c/uid.ics', etag: '"1"', recurrenceId: monday, color: Colors.red);
    final copy = e.copyWith(clearRemote: true);
    expect((copy.remoteId, copy.href, copy.etag, copy.recurrenceId), (null, null, null, null));
    expect((copy.color, copy.rrule, copy.title), (Colors.red, 'FREQ=DAILY', 'Gym'));
  });
}
