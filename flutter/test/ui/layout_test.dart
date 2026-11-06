import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/ui/layout/day_layout.dart';
import 'package:timefix/ui/layout/lane_layout.dart';

EventOccurrence occ(String id, DateTime s, DateTime e, {bool allDay = false}) => EventOccurrence(
      event: CalendarEvent(id: id, calendarId: 'c', title: id, start: s, end: e, allDay: allDay),
      start: s,
      end: e,
      color: Colors.blue,
    );

void main() {
  final day = DateTime(2026, 11, 6);
  DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 6, h, m);

  group('layoutDay', () {
    test('non overlapping events take the full width', () {
      final r = layoutDay(day, [occ('a', at(9), at(10)), occ('b', at(10), at(11))]);
      expect(r.map((p) => (p.column, p.columnCount, p.columnSpan)), [(0, 1, 1), (0, 1, 1)]);
    });

    test('overlapping events share the width', () {
      final r = layoutDay(day, [
        occ('a', at(9), at(11)),
        occ('b', at(9, 30), at(10)),
        occ('c', at(10, 30), at(12)),
      ]);
      final byId = {for (final p in r) p.occurrence.event.id: p};
      expect(byId['a']!.column, 0);
      expect(byId['b']!.column, 1);
      expect(byId['c']!.column, 1);
      expect(byId['a']!.columnCount, 2);
    });

    test('events expand into free columns', () {
      final r = layoutDay(day, [
        occ('a', at(9), at(12)),
        occ('b', at(9), at(10)),
        occ('c', at(9), at(10)),
        occ('d', at(10, 30), at(11)),
      ]);
      final d = r.firstWhere((p) => p.occurrence.event.id == 'd');
      expect(d.columnCount, 3);
      expect(d.column, 1);
      expect(d.columnSpan, 2);
    });

    test('events crossing midnight are clipped to the day', () {
      final r = layoutDay(day, [occ('n', DateTime(2026, 11, 5, 22), at(2))]);
      expect(r.single.startMinutes, 0);
      expect(r.single.endMinutes, 120);
    });

    test('short events get a minimum height', () {
      final r = layoutDay(day, [occ('s', at(9), at(9, 5))]);
      expect(r.single.endMinutes - r.single.startMinutes, 20);
    });
  });

  group('layoutLanes', () {
    final weekStart = DateTime(2026, 11, 2); // Monday

    test('multi-day events span days and stack in lanes', () {
      final layout = layoutLanes(weekStart, 7, [
        occ('long', DateTime(2026, 11, 3), DateTime(2026, 11, 6), allDay: true),
        occ('one', DateTime(2026, 11, 4, 9), DateTime(2026, 11, 4, 10)),
        occ('other', DateTime(2026, 11, 7, 9), DateTime(2026, 11, 7, 10)),
      ]);
      final byId = {for (final i in layout.items) i.occurrence.event.id: i};
      expect((byId['long']!.firstDay, byId['long']!.lastDay, byId['long']!.lane), (1, 3, 0));
      expect(byId['one']!.lane, 1);
      expect(byId['other']!.lane, 0);
    });

    test('events continuing outside the row are flagged', () {
      final layout = layoutLanes(weekStart, 7, [
        occ('x', DateTime(2026, 10, 30), DateTime(2026, 11, 12), allDay: true),
      ]);
      final i = layout.items.single;
      expect((i.firstDay, i.lastDay, i.continuesBefore, i.continuesAfter), (0, 6, true, true));
    });

    test('clip hides overflowing events and counts them per day', () {
      final events = [
        for (var i = 0; i < 4; i++)
          occ('e$i', DateTime(2026, 11, 2, 8 + i), DateTime(2026, 11, 2, 9 + i)),
      ];
      final clip = layoutLanes(weekStart, 7, events).clip(3);
      expect(clip.visible, hasLength(2));
      expect(clip.hiddenPerDay[0], 2);
      expect(clip.hiddenPerDay.skip(1).every((c) => c == 0), isTrue);

      final fits = layoutLanes(weekStart, 7, events.take(3).toList()).clip(3);
      expect(fits.visible, hasLength(3));
    });
  });
}
