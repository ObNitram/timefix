import 'package:flutter_test/flutter_test.dart';
import 'package:timefix/core/date_utils.dart';
import 'package:timefix/data/ical/ical_service.dart';
import 'package:timefix/data/ical/ics_parser.dart';
import 'package:timefix/domain/recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const sample = 'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:-//Test//EN\r\n'
    'X-WR-CALNAME:Équipe\r\n'
    'X-WR-TIMEZONE:Europe/Paris\r\n'
    'BEGIN:VTIMEZONE\r\n'
    'TZID:Europe/Paris\r\n'
    'BEGIN:STANDARD\r\n'
    'DTSTART:19701025T030000\r\n'
    'END:STANDARD\r\n'
    'END:VTIMEZONE\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:weekly@test\r\n'
    'DTSTART;TZID=Europe/Paris:20261102T090000\r\n'
    'DTEND;TZID=Europe/Paris:20261102T100000\r\n'
    'RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20261130T225959Z\r\n'
    'EXDATE;TZID=Europe/Paris:20261116T090000\r\n'
    'SUMMARY:Réunion\\, hebdo\r\n'
    'DESCRIPTION:Ligne 1\\nLigne 2 avec un texte très long qui est replié sur \r\n'
    ' plusieurs lignes\r\n'
    'LOCATION:Salle "A"\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:weekly@test\r\n'
    'RECURRENCE-ID;TZID=Europe/Paris:20261109T090000\r\n'
    'DTSTART;TZID=Europe/Paris:20261109T140000\r\n'
    'DTEND;TZID=Europe/Paris:20261109T150000\r\n'
    'SUMMARY:Réunion déplacée\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:holiday@test\r\n'
    'DTSTART;VALUE=DATE:20261111\r\n'
    'SUMMARY:Armistice\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:utc@test\r\n'
    'DTSTART:20261106T120000Z\r\n'
    'DURATION:PT1H30M\r\n'
    'SUMMARY:UTC\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:cancelled@test\r\n'
    'DTSTART:20261106T120000Z\r\n'
    'STATUS:CANCELLED\r\n'
    'SUMMARY:Annulé\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:windows@test\r\n'
    'DTSTART;TZID="Romance Standard Time":20261106T080000\r\n'
    'DTEND;TZID="Romance Standard Time":20261106T083000\r\n'
    'SUMMARY:Outlook\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  test('parses calendar properties and events', () {
    final cal = IcsParser().parse(sample);
    expect(cal.name, 'Équipe');
    expect(cal.timeZone, 'Europe/Paris');
    expect(cal.events, hasLength(6));

    final weekly = cal.events.first;
    expect(weekly.summary, 'Réunion, hebdo');
    expect(weekly.description, 'Ligne 1\nLigne 2 avec un texte très long qui est replié sur plusieurs lignes');
    expect(weekly.location, 'Salle "A"');
    expect(weekly.start.toUtc(), DateTime.utc(2026, 11, 2, 8));
    expect(weekly.timeZone, 'Europe/Paris');
    expect(weekly.exdates.single.toUtc(), DateTime.utc(2026, 11, 16, 8));

    final holiday = cal.events.firstWhere((e) => e.uid == 'holiday@test');
    expect(holiday.allDay, isTrue);
    expect(holiday.start, DateTime(2026, 11, 11));
    expect(holiday.end, DateTime(2026, 11, 12));

    final utc = cal.events.firstWhere((e) => e.uid == 'utc@test');
    expect(utc.end.difference(utc.start), const Duration(minutes: 90));

    final windows = cal.events.firstWhere((e) => e.uid == 'windows@test');
    expect(windows.start.toUtc(), DateTime.utc(2026, 11, 6, 7));
  });

  test('converts to events with overrides and cancellations', () {
    final cal = IcsParser().parse(sample);
    final events = IcalService.toEvents(cal, 'cal');
    expect(events.where((e) => e.title == 'Annulé'), isEmpty);
    final master = events.firstWhere((e) => e.title == 'Réunion, hebdo');
    expect(master.isRecurring, isTrue);
    expect(master.exdates, hasLength(2)); // EXDATE + RECURRENCE-ID override

    const expander = RecurrenceExpander();
    final occ = expander.occurrences(
        master, DateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 31)));
    // 2, 9 (moved), 16 (excluded), 23, 30 → 2, 23, 30
    expect(occ.map((o) => o.$1.toUtc().day), [2, 23, 30]);

    final moved = events.firstWhere((e) => e.title == 'Réunion déplacée');
    expect(moved.isRecurring, isFalse);
    expect(tz.TZDateTime.from(moved.start, tz.getLocation('Europe/Paris')).hour, 14);
  });

  test('rejects non calendar content', () {
    expect(() => IcsParser().parse('<html></html>'),
        throwsA(isA<IcsParseException>()));
  });

  test('normalizes subscription URLs', () {
    expect(IcalService.normalizeUrl('webcal://example.com/a.ics').toString(),
        'https://example.com/a.ics');
    expect(IcalService.normalizeUrl('example.com/a.ics').scheme, 'https');
    expect(() => IcalService.normalizeUrl('ftp://x'), throwsA(isA<IcalFetchException>()));
  });

  test('parses durations', () {
    expect(IcsParser.parseDuration('P1W'), const Duration(days: 7));
    expect(IcsParser.parseDuration('-PT15M'), const Duration(minutes: -15));
    expect(IcsParser.parseDuration('P1DT2H'), const Duration(days: 1, hours: 2));
  });
}
