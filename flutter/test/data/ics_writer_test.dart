import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timefix/data/ical/ical_service.dart';
import 'package:timefix/data/ical/ics_parser.dart';
import 'package:timefix/data/ical/ics_writer.dart';
import 'package:timefix/domain/models.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  DateTime paris(int y, int m, int d, int h, [int min = 0]) => DateTime.fromMillisecondsSinceEpoch(
      tz.TZDateTime(tz.getLocation('Europe/Paris'), y, m, d, h, min).millisecondsSinceEpoch);

  test('series with override and exdate round trips through the parser', () {
    final master = CalendarEvent(
      id: 'c|uid-1',
      calendarId: 'c',
      remoteId: 'uid-1',
      title: 'Réunion; équipe, hebdo',
      description: 'Ligne 1\nLigne 2',
      location: 'Salle "A"',
      start: paris(2026, 10, 19, 9),
      end: paris(2026, 10, 19, 10),
      timeZone: 'Europe/Paris',
      rrule: 'FREQ=WEEKLY;BYDAY=MO',
      // 26 Oct is a real exclusion, 2 Nov is replaced by the override.
      exdates: [paris(2026, 10, 26, 9), paris(2026, 11, 2, 9)],
      color: const Color(0xFFD50000),
    );
    final override = CalendarEvent(
      id: 'c|uid-1|x',
      calendarId: 'c',
      remoteId: 'uid-1',
      title: 'Réunion déplacée',
      start: paris(2026, 11, 2, 14),
      end: paris(2026, 11, 2, 15),
      timeZone: 'Europe/Paris',
      recurrenceId: paris(2026, 11, 2, 9),
    );

    final ics = IcsWriter.resource([override, master]);
    expect(ics, contains('DTSTART;TZID=Europe/Paris:20261019T090000'));
    expect(ics, contains('RECURRENCE-ID;TZID=Europe/Paris:20261102T090000'));
    expect(ics, contains('EXDATE;TZID=Europe/Paris:20261026T090000'));
    expect(ics, isNot(contains('EXDATE;TZID=Europe/Paris:20261102T090000')));
    expect(ics, contains(r'SUMMARY:Réunion\; équipe\, hebdo'));
    expect(ics, contains(r'DESCRIPTION:Ligne 1\nLigne 2'));
    expect(ics.indexOf('RECURRENCE-ID'), greaterThan(ics.indexOf('RRULE')),
        reason: 'master first');
    for (final line in ics.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75));
    }

    final parsed = IcsParser().parse(ics);
    expect(parsed.events, hasLength(2));
    final events = IcalService.toEvents(parsed, 'c');
    final m = events.firstWhere((e) => e.recurrenceId == null);
    expect(m.title, 'Réunion; équipe, hebdo');
    expect(m.description, 'Ligne 1\nLigne 2');
    expect(m.location, 'Salle "A"');
    expect(m.start, paris(2026, 10, 19, 9));
    expect(m.timeZone, 'Europe/Paris');
    expect(m.rrule, 'FREQ=WEEKLY;BYDAY=MO');
    expect(m.color, const Color(0xFFD50000));
    expect(m.exdates.toSet(), {paris(2026, 10, 26, 9), paris(2026, 11, 2, 9)});
    final o = events.firstWhere((e) => e.recurrenceId != null);
    expect(o.recurrenceId, paris(2026, 11, 2, 9));
    expect(o.start, paris(2026, 11, 2, 14));
  });

  test('all-day and UTC events', () {
    final allDay = CalendarEvent(
      id: 'a',
      calendarId: 'c',
      remoteId: 'a',
      title: 'Congés',
      start: DateTime(2026, 12, 24),
      end: DateTime(2026, 12, 27),
      allDay: true,
    );
    final ics = IcsWriter.resource([allDay]);
    expect(ics, contains('DTSTART;VALUE=DATE:20261224'));
    expect(ics, contains('DTEND;VALUE=DATE:20261227'));
    final back = IcsParser().parse(ics).events.single;
    expect((back.allDay, back.start, back.end), (true, DateTime(2026, 12, 24), DateTime(2026, 12, 27)));

    final utc = allDay.copyWith(
        allDay: false, start: DateTime.utc(2026, 11, 6, 8).toLocal(), end: DateTime.utc(2026, 11, 6, 9).toLocal());
    expect(IcsWriter.resource([utc]), contains('DTSTART:20261106T080000Z'));
  });

  test('long lines are folded without breaking UTF-8 characters', () {
    final line = 'DESCRIPTION:${'é' * 100}';
    final folded = IcsWriter.fold(line);
    expect(IcsParser.unfold(folded).single, line);
    for (final part in folded.split('\r\n')) {
      expect(utf8.encode(part).length, lessThanOrEqualTo(75));
    }
  });
}
