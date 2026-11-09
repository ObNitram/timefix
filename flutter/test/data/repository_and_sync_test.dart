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
import 'package:timefix/data/google/google_calendar_service.dart';
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
            await db.insert('sources', {'id': 'dav', 'type': 'caldav', 'name': 'Dav'});
            await db.insert('calendars', {'id': 'davcal', 'source_id': 'dav', 'name': 'D', 'color': 0xFF000000});
            await db.insert('calendars', {'id': 'c', 'source_id': 's', 'name': 'Cal', 'color': 0xFF000000});
            await db.insert('events', {'id': 'old', 'calendar_id': 'c', 'title': 'Ancien',
              'start_ms': 0, 'end_ms': 3600000});
          },
        ));
    await v1.close();

    // Pretend a v2 sync stored a ctag (the v2 migration adds the column).
    final v2 = await databaseFactoryFfi.openDatabase(path);
    await v2.execute('ALTER TABLE calendars ADD COLUMN sync_token TEXT');
    await v2.execute("UPDATE calendars SET sync_token = 'ctag-1'");
    await v2.execute('ALTER TABLE sources ADD COLUMN username TEXT');
    await v2.execute('ALTER TABLE events ADD COLUMN href TEXT');
    await v2.execute('ALTER TABLE events ADD COLUMN etag TEXT');
    await v2.execute('ALTER TABLE events ADD COLUMN recurrence_id INTEGER');
    await v2.execute('CREATE INDEX idx_events_href ON events(href)');
    await v2.setVersion(2);
    await v2.close();

    final migrated = await SqliteCalendarRepository.open(factory: databaseFactoryFfi, path: path);
    // v3: CalDAV calendars are downloaded again (to get their VALARMs).
    expect((await migrated.getCalendar('davcal'))!.syncToken, isNull);
    expect((await migrated.getCalendar('c'))!.syncToken, 'ctag-1');
    expect((await migrated.getEvent('old'))!.title, 'Ancien');
    await migrated.upsertEvent((await migrated.getEvent('old'))!
        .copyWith(href: 'https://x/a.ics', etag: '"e"', recurrenceId: DateTime(2026)));
    final back = (await migrated.getEvent('old'))!;
    expect((back.href, back.etag, back.recurrenceId), ('https://x/a.ics', '"e"', DateTime(2026)));
    await migrated.upsertEvent((await migrated.getEvent('old'))!.copyWith(extraAlarms: const ['BEGIN:VALARM\r\nACTION:EMAIL\r\nEND:VALARM']));
    expect((await migrated.getEvent('old'))!.extraAlarms.single, contains('EMAIL'));
    expect(await migrated.eventsByHref('c', 'https://x/a.ics'), hasLength(1));
    // v3: reminders.
    await migrated.upsertEvent((await migrated.getEvent('old'))!
        .copyWith(reminders: const [Reminder(10, ReminderType.alarm)]));
    expect((await migrated.getEvent('old'))!.reminders, const [Reminder(10, ReminderType.alarm)]);
    await migrated.setLocalReminders('ro|1', const [Reminder(30, ReminderType.push)]);
    expect(await migrated.localReminders(), {'ro|1': const [Reminder(30, ReminderType.push)]});
    await migrated.setLocalReminders('ro|1', const [], keepEmpty: true);
    expect(await migrated.localReminders(), {'ro|1': const <Reminder>[]});
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
      // The editor sends the occurrence's own start and end.
      edited: sixth.event.copyWith(title: 'Daily', start: sixth.start, end: sixth.end),
      scope: RecurrenceScope.thisAndFollowing,
    );
    occ = await occurrences(range);
    expect(occ.where((o) => o.title == 'Standup'), hasLength(5)); // 4 + moved one
    // The new series keeps the 5 remaining occurrences of COUNT=10.
    expect(occ.where((o) => o.title == 'Daily'), hasLength(5));

    // Delete all of the first series.
    await events.delete(occ.firstWhere((o) => o.title == 'Standup' && o.event.isRecurring));
    occ = await occurrences(range);
    expect(occ.where((o) => o.title == 'Standup'), hasLength(1));
  });

  test('local series moved from Monday to Tuesday for all occurrences', () async {
    await events.create(CalendarEvent(
      id: 'w',
      calendarId: 'local:default',
      title: 'Gym',
      start: DateTime(2026, 11, 2, 18), // Monday
      end: DateTime(2026, 11, 2, 19),
      rrule: 'FREQ=WEEKLY;BYDAY=MO',
    ));
    final range = DateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    final second = (await occurrences(range))[1];
    await events.update(
      original: second,
      edited: second.event.copyWith(start: DateTime(2026, 11, 10, 18), end: DateTime(2026, 11, 10, 19)),
    );
    final occ = await occurrences(range);
    expect(occ.map((o) => o.start.weekday).toSet(), {DateTime.tuesday});
    expect(occ.first.start, DateTime(2026, 11, 3, 18));
  });

  test('one occurrence moved to a Google calendar is created there alone', () async {
    google.calendars.add(gcal.CalendarListEntry()
      ..id = 'primary@example.com'
      ..summary = 'Perso'
      ..accessRole = 'owner');
    await sync.addGoogleAccount();
    final googleCal = (await repo.getCalendars()).firstWhere((c) => c.remoteId == 'primary@example.com');
    await events.create(CalendarEvent(
      id: 'd',
      calendarId: 'local:default',
      title: 'Standup',
      start: DateTime(2026, 11, 2, 9),
      end: DateTime(2026, 11, 2, 9, 15),
      rrule: 'FREQ=DAILY;COUNT=5',
    ));
    final range = DateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    final third = (await occurrences(range))[2];
    await events.update(
      original: third,
      edited: third.event.copyWith(calendarId: googleCal.id, start: third.start, end: third.end),
      scope: RecurrenceScope.thisEvent,
    );
    final created = google.events['primary@example.com']!.single;
    expect(created.recurrence, isNull);
    expect(created.start!.dateTime!.toLocal(), DateTime(2026, 11, 4, 9));
    final occ = await occurrences(range);
    expect(occ.where((o) => o.title == 'Standup'), hasLength(5), reason: '4 local + 1 on Google');
  });

  test('a single Google account; another signed-in account is never synced', () async {
    google.calendars.add(gcal.CalendarListEntry()
      ..id = 'a@example.com'
      ..summary = 'A'
      ..accessRole = 'owner');
    google.email = 'a@example.com';
    final source = await sync.addGoogleAccount();
    await expectLater(sync.addGoogleAccount(), throwsA(isA<GoogleAccountLimitException>()));

    // The app is now signed in to B (e.g. through the account picker).
    google.email = 'b@example.com';
    google.calendars
      ..clear()
      ..add(gcal.CalendarListEntry()
        ..id = 'b@example.com'
        ..summary = 'B'
        ..accessRole = 'owner');
    final report = await sync.syncAll();
    expect(report.errors.keys, [source.id]);
    expect((await repo.getCalendars()).where((c) => c.sourceId == source.id).map((c) => c.name), ['A']);
    final cal = (await repo.getCalendars()).firstWhere((c) => c.name == 'A');
    await expectLater(
        events.create(CalendarEvent(
            id: 'x', calendarId: cal.id, title: 'x', start: DateTime(2026, 11, 2, 9), end: DateTime(2026, 11, 2, 10))),
        throwsA(isA<GoogleAccountMismatchException>()));
    expect(google.events['a@example.com'], isNull);
  });
}

List<int> _icsBytes() => const Utf8Codec().encode(_ics);
