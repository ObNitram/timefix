// End-to-end tests of the app's CalDAV support against a running TimeFix
// server. Skipped unless TIMEFIX_CALDAV_URL is set, e.g.:
//   TIMEFIX_CALDAV_URL=http://127.0.0.1:5080 TIMEFIX_CALDAV_ADMIN=admin:password \
//     flutter test test/integration/caldav_server_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timefix/core/date_utils.dart';
import 'package:timefix/data/caldav/caldav_client.dart';
import 'package:timefix/data/credentials.dart';
import 'package:timefix/data/db/sqlite_calendar_repository.dart';
import 'package:timefix/data/event_service.dart';
import 'package:timefix/data/ical/ical_service.dart';
import 'package:timefix/data/sync/sync_service.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/state/providers.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../helpers.dart';

final _serverUrl = Platform.environment['TIMEFIX_CALDAV_URL'];
final _admin = Platform.environment['TIMEFIX_CALDAV_ADMIN'] ?? 'admin:admin-dev-password';

/// Instant of a wall-clock time in Paris, whatever the machine's time zone.
DateTime paris(int y, int m, int d, [int h = 0]) => DateTime.fromMillisecondsSinceEpoch(
    tz.TZDateTime(tz.getLocation('Europe/Paris'), y, m, d, h).millisecondsSinceEpoch);

int parisDay(DateTime d) => tz.TZDateTime.from(d, tz.getLocation('Europe/Paris')).day;

void main() {
  final skip = _serverUrl == null ? 'TIMEFIX_CALDAV_URL not set' : null;

  late SqliteCalendarRepository repo;
  late SyncService sync;
  late EventService events;
  late String username;
  const password = 'integration-password';

  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Paris'));
  });

  setUp(() async {
    if (skip != null) return;
    // A fresh account per test, created through the admin API.
    username = 'it${DateTime.now().microsecondsSinceEpoch}';
    final r = await http.post(Uri.parse('$_serverUrl/api/admin/users'),
        headers: {
          'Authorization': 'Basic ${base64.encode(utf8.encode(_admin))}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'username': username, 'password': password}));
    expect(r.statusCode, 201, reason: r.body);

    repo = await SqliteCalendarRepository.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    sync = SyncService(
      repository: repo,
      ical: IcalService(),
      google: FakeGoogleGateway(),
      credentials: InMemoryCredentialStore(),
    );
    events = EventService(repository: repo, google: FakeGoogleGateway(), sync: sync);
  });

  tearDown(() async {
    if (skip == null) await repo.close();
  });

  CalDavClient server() => CalDavClient(username: username, password: password);

  Future<CalendarInfo> connect() async {
    await sync.addCalDavAccount(serverUrl: _serverUrl!, username: username, password: password);
    return (await repo.getCalendars()).single;
  }

  Future<List<EventOccurrence>> occurrences(DateRange range) async {
    final cals = {for (final c in await repo.getCalendars()) c.id: c};
    return expandEvents(await repo.eventsForRange(range, cals.keys.toSet()), cals, range);
  }

  Future<List<CalDavObject>> serverObjects(CalendarInfo cal) =>
      server().fetchEvents(Uri.parse(cal.remoteId!));

  final november = DateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1));

  test('wrong password is reported and nothing is saved', () async {
    await expectLater(
      sync.addCalDavAccount(serverUrl: _serverUrl!, username: username, password: 'wrong-password'),
      throwsA(isA<CalDavAuthException>()),
    );
    expect(await repo.getSources(), isEmpty);
  }, skip: skip);

  test('connecting discovers the default calendar', () async {
    final cal = await connect();
    final source = (await repo.getSources()).single;
    expect(source.type, SourceType.caldav);
    expect(source.username, username);
    expect(source.url, endsWith('/dav/calendars/$username/'));
    expect(cal.name, 'Personnel');
    expect(cal.readOnly, isFalse);
    expect(cal.color, const Color(0xFF039BE5));
    expect(cal.syncToken, startsWith('ctag-'));
  }, skip: skip);

  test('create, update and delete a single event', () async {
    final cal = await connect();
    await events.create(CalendarEvent(
      id: events.newEventId(),
      calendarId: cal.id,
      title: 'Dentiste',
      location: 'Cabinet, 2e étage',
      start: paris(2026, 11, 10, 9),
      end: paris(2026, 11, 10, 10),
    ));
    var objects = await serverObjects(cal);
    expect(objects, hasLength(1));
    expect(objects.single.data, contains('SUMMARY:Dentiste'));
    expect(objects.single.data, contains('DTSTART;TZID=Europe/Paris:20261110T090000'));
    final local = (await occurrences(november)).single;
    expect(local.event.etag, objects.single.etag);

    await events.update(original: local, edited: local.event.copyWith(title: 'Dentiste (déplacé)'));
    objects = await serverObjects(cal);
    expect(objects.single.data, contains('SUMMARY:Dentiste (déplacé)'));
    expect(objects.single.data, contains(r'LOCATION:Cabinet\, 2e étage'));

    await events.delete((await occurrences(november)).single);
    expect(await serverObjects(cal), isEmpty);
    expect(await occurrences(november), isEmpty);
  }, skip: skip);

  test('recurring event: this occurrence, following, all', () async {
    final cal = await connect();
    await events.create(CalendarEvent(
      id: events.newEventId(),
      calendarId: cal.id,
      title: 'Sport',
      start: paris(2026, 11, 2, 18),
      end: paris(2026, 11, 2, 19),
      rrule: 'FREQ=WEEKLY',
    ));
    var occ = await occurrences(november);
    expect(occ.map((o) => parisDay(o.start)), [2, 9, 16, 23, 30]);

    // Move the 9 Nov occurrence only → RECURRENCE-ID override on the server.
    final second = occ[1];
    await events.update(
      original: second,
      edited: second.event.copyWith(
          title: 'Sport (décalé)', start: paris(2026, 11, 10, 18), end: paris(2026, 11, 10, 19)),
      scope: RecurrenceScope.thisEvent,
    );
    var data = (await serverObjects(cal)).single.data;
    expect(data, contains('RECURRENCE-ID;TZID=Europe/Paris:20261109T180000'));
    expect(data, isNot(contains('EXDATE')));

    // The server copy, downloaded again, gives the same occurrences.
    await sync.syncCalDavCalendar(cal);
    occ = await occurrences(november);
    expect(occ.map((o) => (parisDay(o.start), o.title)), [
      (2, 'Sport'),
      (10, 'Sport (décalé)'),
      (16, 'Sport'),
      (23, 'Sport'),
      (30, 'Sport'),
    ]);

    // Deleting the moved occurrence turns it into an EXDATE.
    await events.delete(occ[1]);
    data = (await serverObjects(cal)).single.data;
    expect(data, isNot(contains('RECURRENCE-ID')));
    expect(data, contains('EXDATE;TZID=Europe/Paris:20261109T180000'));

    // Delete from 23 Nov onwards → UNTIL.
    occ = await occurrences(november);
    await events.delete(occ.firstWhere((o) => parisDay(o.start) == 23), scope: RecurrenceScope.thisAndFollowing);
    data = (await serverObjects(cal)).single.data;
    expect(data, contains('UNTIL='));
    expect((await occurrences(november)).map((o) => parisDay(o.start)), [2, 16]);

    await events.delete((await occurrences(november)).first, scope: RecurrenceScope.all);
    expect(await serverObjects(cal), isEmpty);
  }, skip: skip);

  test('changes made elsewhere are synced, and stale edits are refused', () async {
    final cal = await connect();
    // Another client creates an event.
    final other = server();
    final href = Uri.parse(cal.remoteId!).resolve('other-client.ics');
    final etag = await other.put(
        href,
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Other//EN\r\nBEGIN:VEVENT\r\nUID:other-1\r\n'
        'DTSTAMP:20261101T000000Z\r\nDTSTART:20261112T080000Z\r\nDTEND:20261112T090000Z\r\n'
        'SUMMARY:Créé ailleurs\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
        create: true);
    final report = await sync.syncAll();
    expect(report.hasErrors, isFalse);
    final occ = (await occurrences(november)).single;
    expect(occ.title, 'Créé ailleurs');

    // It is changed again elsewhere; our copy is now stale.
    await other.put(href, (await serverObjects(cal)).single.data.replaceAll('Créé ailleurs', 'Version serveur'),
        ifMatch: etag);
    await expectLater(
      events.update(original: occ, edited: occ.event.copyWith(title: 'Version locale')),
      throwsA(isA<CalDavConflictException>()),
    );
    // The conflict refreshed the local data; nothing was overwritten.
    expect((await occurrences(november)).single.title, 'Version serveur');
    expect((await serverObjects(cal)).single.data, contains('SUMMARY:Version serveur'));
  }, skip: skip);

  test('new calendar created from the app (MKCALENDAR)', () async {
    await connect();
    final source = (await repo.getSources()).single;
    await sync.createCalDavCalendar(source, 'Travail', const Color(0xFF33B679));
    final cals = await repo.getCalendars();
    expect(cals.map((c) => c.name), containsAll(['Personnel', 'Travail']));
    final work = cals.firstWhere((c) => c.name == 'Travail');
    expect(work.color, const Color(0xFF33B679));

    await events.create(CalendarEvent(
      id: events.newEventId(),
      calendarId: work.id,
      title: 'Projet',
      start: DateTime(2026, 11, 20),
      end: DateTime(2026, 11, 21),
      allDay: true,
    ));
    expect((await serverObjects(work)).single.data, contains('DTSTART;VALUE=DATE:20261120'));
  }, skip: skip);
}
