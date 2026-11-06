import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timefix/core/date_utils.dart';
import 'package:timefix/data/db/sqlite_calendar_repository.dart';
import 'package:timefix/data/event_service.dart';
import 'package:timefix/data/ical/ical_service.dart';
import 'package:timefix/data/sync/sync_service.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/domain/reminders.dart';
import 'package:timefix/state/providers.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../helpers.dart';

const _ics = 'BEGIN:VCALENDAR\r\nX-WR-CALNAME:Jours fériés\r\n'
    'BEGIN:VEVENT\r\nUID:a\r\nDTSTART;VALUE=DATE:20261111\r\nSUMMARY:Armistice\r\nEND:VEVENT\r\n'
    'BEGIN:VEVENT\r\nUID:b\r\nDTSTART;VALUE=DATE:20261225\r\nRRULE:FREQ=YEARLY\r\nSUMMARY:Noël\r\nEND:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  late SqliteCalendarRepository repo;
  late FakeGoogleGateway google;
  late SyncService sync;
  late EventService events;

  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
  });

  setUp(() async {
    repo = await SqliteCalendarRepository.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    google = FakeGoogleGateway();
    final client = MockClient((req) async {
      if (req.url.path.endsWith('.ics')) {
        return http.Response.bytes(_icsBytes(), 200);
      }
      return http.Response('not found', 404);
    });
    sync = SyncService(repository: repo, ical: IcalService(client: client), google: google);
    events = EventService(repository: repo, google: google, sync: sync);
    await sync.ensureLocalCalendar('Mon calendrier');
  });

  tearDown(() => repo.close());

  Future<List<EventOccurrence>> occurrences(DateRange range) async {
    final cals = {for (final c in await repo.getCalendars()) c.id: c};
    return expandEvents(await repo.eventsForRange(range, cals.keys.toSet()), cals, range);
  }

  test('sqlite round trip keeps all-day dates and exdates', () async {
    final e = CalendarEvent(
      id: 'x',
      calendarId: 'local:default',
      title: 'Daily',
      start: DateTime(2026, 11, 2),
      end: DateTime(2026, 11, 3),
      allDay: true,
      rrule: 'FREQ=DAILY',
      exdates: [DateTime(2026, 11, 4)],
      color: const Color(0xFFD50000),
    );
    await repo.upsertEvent(e);
    final back = (await repo.getEvent('x'))!;
    expect(back.start, DateTime(2026, 11, 2));
    expect(back.end, DateTime(2026, 11, 3));
    expect(back.exdates, [DateTime(2026, 11, 4)]);
    expect(back.color, const Color(0xFFD50000));
    final occ = await occurrences(DateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 8)));
    expect(occ.map((o) => o.start.day), [2, 3, 5, 6, 7]);
  });

  test('a version 1 database is migrated to the current version', () async {
    final path = '${Directory.systemTemp.path}/timefix-v1-${DateTime.now().microsecondsSinceEpoch}.db';
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE sources (id TEXT PRIMARY KEY, type TEXT NOT NULL, name TEXT NOT NULL, '
                'url TEXT, account_email TEXT, last_synced_at INTEGER, last_error TEXT)');
            await db.execute('CREATE TABLE calendars (id TEXT PRIMARY KEY, source_id TEXT NOT NULL, remote_id TEXT, '
                'name TEXT NOT NULL, color INTEGER NOT NULL, visible INTEGER NOT NULL DEFAULT 1, '
                'read_only INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0)');
            await db.execute('CREATE TABLE events (id TEXT PRIMARY KEY, calendar_id TEXT NOT NULL, remote_id TEXT, '
                'recurring_remote_id TEXT, title TEXT NOT NULL, description TEXT, location TEXT, '
                'start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, all_day INTEGER NOT NULL DEFAULT 0, '
                'time_zone TEXT, rrule TEXT, exdates TEXT, color INTEGER, updated_at INTEGER)');
            await db.insert('sources', {'id': 's', 'type': 'local', 'name': 'Local'});
            await db.insert('calendars', {'id': 'c', 'source_id': 's', 'name': 'Cal', 'color': 0xFF000000});
            await db.insert('events', {'id': 'old', 'calendar_id': 'c', 'title': 'Ancien',
              'start_ms': 0, 'end_ms': 3600000});
          },
        ));
    await v1.close();

    final migrated = await SqliteCalendarRepository.open(factory: databaseFactoryFfi, path: path);
    expect((await migrated.getEvent('old'))!.title, 'Ancien');
    await migrated.upsertEvent((await migrated.getEvent('old'))!
        .copyWith(href: 'https://x/a.ics', etag: '"e"', recurrenceId: DateTime(2026)));
    final back = (await migrated.getEvent('old'))!;
    expect((back.href, back.etag, back.recurrenceId), ('https://x/a.ics', '"e"', DateTime(2026)));
    await migrated.upsertCalendar((await migrated.getCalendar('c'))!.copyWith(syncToken: 'ctag-1'));
    expect((await migrated.getCalendar('c'))!.syncToken, 'ctag-1');
    expect(await migrated.eventsByHref('c', 'https://x/a.ics'), hasLength(1));
    // v3: reminders.
    await migrated.upsertEvent((await migrated.getEvent('old'))!
        .copyWith(reminders: const [Reminder(10, ReminderType.alarm)]));
    expect((await migrated.getEvent('old'))!.reminders, const [Reminder(10, ReminderType.alarm)]);
    await migrated.setLocalReminders('ro|1', const [Reminder(30, ReminderType.push)]);
    expect(await migrated.localReminders(), {'ro|1': const [Reminder(30, ReminderType.push)]});
    await migrated.setLocalReminders('ro|1', const []);
    expect(await migrated.localReminders(), isEmpty);
    await migrated.close();
    await File(path).delete();
  });

  test('updating a calendar or source keeps its events', () async {
    await repo.upsertEvent(CalendarEvent(
        id: 'k',
        calendarId: 'local:default',
        title: 'Keep me',
        start: DateTime(2026, 11, 2, 9),
        end: DateTime(2026, 11, 2, 10)));
    final cal = (await repo.getCalendar('local:default'))!;
    await repo.upsertCalendar(cal.copyWith(visible: false));
    await repo.upsertCalendar(cal.copyWith(visible: true, name: 'Renamed'));
    await repo.upsertSource((await repo.getSource('local'))!.copyWith(name: 'x'));
    expect(await repo.getEvent('k'), isNotNull);
    expect((await repo.getCalendar('local:default'))!.name, 'Renamed');
  });

  test('iCal subscription is imported read only and can be removed', () async {
    final source = await sync.addIcalSubscription(
        url: 'webcal://example.com/feries.ics', color: Colors.red);
    expect(source.name, 'Jours fériés');
    expect(source.url, 'https://example.com/feries.ics');
    final cal = (await repo.getCalendars()).firstWhere((c) => c.sourceId == source.id);
    expect(cal.readOnly, isTrue);

    final nov = await occurrences(DateRange(DateTime(2027, 12, 1), DateTime(2028, 1, 1)));
    expect(nov.single.title, 'Noël');

    await sync.syncSource(source);
    expect((await repo.getSource(source.id))!.lastSyncedAt, isNotNull);

    await sync.removeSource(source);
    expect(await repo.getCalendars(), hasLength(1));
    expect(await repo.eventsForRange(
        DateRange(DateTime(2026), DateTime(2028)), {cal.id}), isEmpty);
  });

  test('invalid iCal URL does not create a source', () async {
    await expectLater(
      sync.addIcalSubscription(url: 'https://example.com/missing', color: Colors.red),
      throwsA(isA<IcalFetchException>()),
    );
    expect((await repo.getSources()).length, 1);
  });

  test('Google account sync, create, edit and delete', () async {
    google.calendars.add(gcal.CalendarListEntry()
      ..id = 'primary@example.com'
      ..summary = 'Perso'
      ..backgroundColor = '#33b679'
      ..accessRole = 'owner'
      ..primary = true);
    google.calendars.add(gcal.CalendarListEntry()
      ..id = 'holidays'
      ..summary = 'Fêtes'
      ..accessRole = 'reader');
    google.events['primary@example.com'] = [
      gcal.Event()
        ..id = 'ev1'
        ..summary = 'Rendez-vous'
        ..start = gcal.EventDateTime(dateTime: DateTime.utc(2026, 11, 10, 9))
        ..end = gcal.EventDateTime(dateTime: DateTime.utc(2026, 11, 10, 10)),
      gcal.Event()
        ..id = 'gone'
        ..status = 'cancelled',
    ];

    final source = await sync.addGoogleAccount();
    expect(source.accountEmail, 'user@example.com');
    final cals = (await repo.getCalendars()).where((c) => c.sourceId == source.id).toList();
    expect(cals.map((c) => c.name), containsAll(['Perso', 'Fêtes']));
    final perso = cals.firstWhere((c) => c.name == 'Perso');
    expect(perso.readOnly, isFalse);
    expect(cals.firstWhere((c) => c.name == 'Fêtes').readOnly, isTrue);

    final range = DateRange(DateTime(2026, 11, 9), DateTime(2026, 11, 12));
    var occ = await occurrences(range);
    expect(occ.single.title, 'Rendez-vous');

    // Create
    await events.create(CalendarEvent(
      id: events.newEventId(),
      calendarId: perso.id,
      title: 'Nouveau',
      start: DateTime(2026, 11, 11, 14),
      end: DateTime(2026, 11, 11, 15),
    ));
    expect(google.events['primary@example.com']!.map((e) => e.summary), contains('Nouveau'));
    occ = await occurrences(range);
    expect(occ.map((o) => o.title), containsAll(['Rendez-vous', 'Nouveau']));

    // Edit
    final rdv = occ.firstWhere((o) => o.title == 'Rendez-vous');
    await events.update(original: rdv, edited: rdv.event.copyWith(title: 'RDV modifié'));
    occ = await occurrences(range);
    expect(occ.map((o) => o.title), contains('RDV modifié'));

    // Delete
    await events.delete(occ.firstWhere((o) => o.title == 'Nouveau'));
    occ = await occurrences(range);
    expect(occ.map((o) => o.title), isNot(contains('Nouveau')));

    // Read-only calendar refuses writes
    await expectLater(
      events.create(CalendarEvent(
          id: 'z',
          calendarId: cals.firstWhere((c) => c.name == 'Fêtes').id,
          title: 'x',
          start: DateTime(2026, 11, 11),
          end: DateTime(2026, 11, 12),
          allDay: true)),
      throwsA(isA<ReadOnlyCalendarException>()),
    );
  });

  test('local recurring edits: this, following, all', () async {
    final master = CalendarEvent(
      id: 'r',
      calendarId: 'local:default',
      title: 'Standup',
      start: DateTime(2026, 11, 2, 9),
      end: DateTime(2026, 11, 2, 9, 15),
      rrule: 'FREQ=DAILY;COUNT=10',
    );
    await events.create(master);
    final range = DateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    var occ = await occurrences(range);
    expect(occ, hasLength(10));

    // This event only: move the 3rd occurrence to 10:00.
    final third = occ[2];
    await events.update(
      original: third,
      edited: third.event.copyWith(
          start: DateTime(2026, 11, 4, 10), end: DateTime(2026, 11, 4, 10, 15)),
      scope: RecurrenceScope.thisEvent,
    );
    occ = await occurrences(range);
    expect(occ, hasLength(10));
    expect(occ.where((o) => o.start == DateTime(2026, 11, 4, 10)), hasLength(1));

    // This and following: rename from the 6th occurrence.
    final sixth = occ.firstWhere((o) => o.start == DateTime(2026, 11, 7, 9));
    await events.update(
      original: sixth,
      edited: sixth.event.copyWith(title: 'Daily'),
      scope: RecurrenceScope.thisAndFollowing,
    );
    occ = await occurrences(range);
    expect(occ.where((o) => o.title == 'Standup'), hasLength(5)); // 4 + moved one
    expect(occ.where((o) => o.title == 'Daily').length, greaterThanOrEqualTo(5));

    // Delete all of the first series.
    await events.delete(occ.firstWhere((o) => o.title == 'Standup' && o.event.isRecurring));
    occ = await occurrences(range);
    expect(occ.where((o) => o.title == 'Standup'), hasLength(1));
  });
}

List<int> _icsBytes() => const Utf8Codec().encode(_ics);
