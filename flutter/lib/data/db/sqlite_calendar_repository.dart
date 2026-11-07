import 'dart:convert';
import 'dart:ui' show Color;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/date_utils.dart';
import '../../domain/models.dart';
import '../../domain/reminders.dart';
import '../calendar_repository.dart';

/// SQLite implementation of [CalendarRepository].
///
/// Storage conventions: timed instants are stored as UTC epoch milliseconds;
/// all-day dates as the epoch milliseconds of that date at 00:00 UTC, so they
/// do not move when the device time zone changes.
class SqliteCalendarRepository implements CalendarRepository {
  SqliteCalendarRepository(this._db);

  final Database _db;

  static const _version = 3;

  static Future<SqliteCalendarRepository> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'timefix.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await _createSchema(db);
          await _migrateToV2(db);
          await _migrateToV3(db);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) await _migrateToV2(db);
          if (from < 3) await _migrateToV3(db);
        },
      ),
    );
    return SqliteCalendarRepository(db);
  }

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE sources (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        url TEXT,
        account_email TEXT,
        last_synced_at INTEGER,
        last_error TEXT
      )''');
    batch.execute('''
      CREATE TABLE calendars (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        remote_id TEXT,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        visible INTEGER NOT NULL DEFAULT 1,
        read_only INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        calendar_id TEXT NOT NULL REFERENCES calendars(id) ON DELETE CASCADE,
        remote_id TEXT,
        recurring_remote_id TEXT,
        title TEXT NOT NULL,
        description TEXT,
        location TEXT,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        all_day INTEGER NOT NULL DEFAULT 0,
        time_zone TEXT,
        rrule TEXT,
        exdates TEXT,
        color INTEGER,
        updated_at INTEGER
      )''');
    batch.execute('CREATE INDEX idx_events_calendar ON events(calendar_id)');
    batch.execute('CREATE INDEX idx_events_start ON events(start_ms)');
    batch.execute('CREATE INDEX idx_events_end ON events(end_ms)');
    await batch.commit(noResult: true);
  }

  /// v2: CalDAV support.
  static Future<void> _migrateToV2(Database db) async {
    final batch = db.batch();
    batch.execute('ALTER TABLE sources ADD COLUMN username TEXT');
    batch.execute('ALTER TABLE calendars ADD COLUMN sync_token TEXT');
    batch.execute('ALTER TABLE events ADD COLUMN href TEXT');
    batch.execute('ALTER TABLE events ADD COLUMN etag TEXT');
    batch.execute('ALTER TABLE events ADD COLUMN recurrence_id INTEGER');
    batch.execute('CREATE INDEX idx_events_href ON events(href)');
    await batch.commit(noResult: true);
  }

  /// v3: reminders.
  static Future<void> _migrateToV3(Database db) async {
    final batch = db.batch();
    batch.execute('ALTER TABLE events ADD COLUMN reminders TEXT');
    batch.execute('ALTER TABLE events ADD COLUMN extra_alarms TEXT');
    // CalDAV events were stored without their VALARMs: download them again.
    batch.execute(
        "UPDATE calendars SET sync_token = NULL WHERE source_id IN (SELECT id FROM sources WHERE type = 'caldav')");
    // Reminders kept on this device only (read-only calendars, Google
    // full-screen / alarm reminders). Not tied to the events table because
    // synchronisation replaces event rows.
    batch.execute('''
      CREATE TABLE local_reminders (
        event_id TEXT PRIMARY KEY,
        reminders TEXT NOT NULL
      )''');
    await batch.commit(noResult: true);
  }

  Future<void> close() => _db.close();

  // ---------------------------------------------------------------------------
  // Sources
  // ---------------------------------------------------------------------------

  @override
  Future<List<CalendarSource>> getSources() async {
    final rows = await _db.query('sources', orderBy: 'rowid');
    return rows.map(_sourceFromRow).toList();
  }

  @override
  Future<CalendarSource?> getSource(String id) async {
    final rows = await _db.query('sources', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _sourceFromRow(rows.first);
  }

  /// Updates the row, or inserts it when missing. `INSERT OR REPLACE` must not
  /// be used for parent tables: it deletes the row first, which cascades to
  /// the children (calendars / events).
  Future<void> _upsert(String table, Map<String, Object?> values) =>
      _db.transaction((txn) async {
        final updated = await txn.update(table, values,
            where: 'id = ?', whereArgs: [values['id']]);
        if (updated == 0) await txn.insert(table, values);
      });

  @override
  Future<void> upsertSource(CalendarSource s) => _upsert(
        'sources',
        {
          'id': s.id,
          'type': s.type.name,
          'name': s.name,
          'url': s.url,
          'account_email': s.accountEmail,
          'username': s.username,
          'last_synced_at': s.lastSyncedAt?.millisecondsSinceEpoch,
          'last_error': s.lastError,
        },
      );

  @override
  Future<void> deleteSource(String id) =>
      _db.delete('sources', where: 'id = ?', whereArgs: [id]);

  CalendarSource _sourceFromRow(Map<String, Object?> r) => CalendarSource(
        id: r['id'] as String,
        type: SourceType.fromName(r['type'] as String),
        name: r['name'] as String,
        url: r['url'] as String?,
        accountEmail: r['account_email'] as String?,
        username: r['username'] as String?,
        lastSyncedAt: r['last_synced_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['last_synced_at'] as int),
        lastError: r['last_error'] as String?,
      );

  // ---------------------------------------------------------------------------
  // Calendars
  // ---------------------------------------------------------------------------

  @override
  Future<List<CalendarInfo>> getCalendars() async {
    final rows = await _db.query('calendars', orderBy: 'sort_order, name');
    return rows.map(_calendarFromRow).toList();
  }

  @override
  Future<CalendarInfo?> getCalendar(String id) async {
    final rows = await _db.query('calendars', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _calendarFromRow(rows.first);
  }

  @override
  Future<void> upsertCalendar(CalendarInfo c) => _upsert(
        'calendars',
        {
          'id': c.id,
          'source_id': c.sourceId,
          'remote_id': c.remoteId,
          'name': c.name,
          'color': c.color.toARGB32(),
          'visible': c.visible ? 1 : 0,
          'read_only': c.readOnly ? 1 : 0,
          'sort_order': c.sortOrder,
          'sync_token': c.syncToken,
        },
      );

  @override
  Future<void> deleteCalendar(String id) =>
      _db.delete('calendars', where: 'id = ?', whereArgs: [id]);

  CalendarInfo _calendarFromRow(Map<String, Object?> r) => CalendarInfo(
        id: r['id'] as String,
        sourceId: r['source_id'] as String,
        remoteId: r['remote_id'] as String?,
        name: r['name'] as String,
        color: Color(r['color'] as int),
        visible: (r['visible'] as int) == 1,
        readOnly: (r['read_only'] as int) == 1,
        sortOrder: r['sort_order'] as int,
        syncToken: r['sync_token'] as String?,
      );

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  @override
  Future<List<CalendarEvent>> eventsForRange(
      DateRange range, Set<String> calendarIds) async {
    if (calendarIds.isEmpty) return const [];
    // One day of slack on each side covers all-day events stored in UTC.
    final from = addDays(range.start, -1).millisecondsSinceEpoch;
    final to = addDays(range.end, 1).millisecondsSinceEpoch;
    final placeholders = List.filled(calendarIds.length, '?').join(',');
    final rows = await _db.rawQuery('''
      SELECT * FROM events
      WHERE calendar_id IN ($placeholders)
        AND start_ms < ?
        AND (rrule IS NOT NULL OR end_ms >= ?)
    ''', [...calendarIds, to, from]);
    return rows.map(_eventFromRow).toList();
  }

  @override
  Future<CalendarEvent?> getEvent(String id) async {
    final rows = await _db.query('events', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _eventFromRow(rows.first);
  }

  @override
  Future<void> upsertEvent(CalendarEvent e) => _db.insert('events', _eventToRow(e),
      conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> deleteEvent(String id) =>
      _db.delete('events', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> replaceEvents(String calendarId, List<CalendarEvent> events) =>
      _db.transaction((txn) async {
        await txn.delete('events', where: 'calendar_id = ?', whereArgs: [calendarId]);
        final batch = txn.batch();
        for (final e in events) {
          batch.insert('events', _eventToRow(e),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      });

  @override
  Future<Map<String, List<Reminder>>> localReminders([Set<String>? eventIds]) async {
    final rows = await _db.query('local_reminders');
    return {
      for (final r in rows)
        if (eventIds == null || eventIds.contains(r['event_id']))
          r['event_id'] as String: Reminder.decodeList(r['reminders'] as String),
    };
  }

  @override
  Future<void> setLocalReminders(String key, List<Reminder> reminders, {bool keepEmpty = false}) async {
    if (reminders.isEmpty && !keepEmpty) {
      await _db.delete('local_reminders', where: 'event_id = ?', whereArgs: [key]);
    } else {
      await _db.insert('local_reminders',
          {'event_id': key, 'reminders': Reminder.encodeList(reminders)},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<List<CalendarEvent>> eventsByHref(String calendarId, String href) async {
    final rows = await _db.query('events',
        where: 'calendar_id = ? AND href = ?', whereArgs: [calendarId, href]);
    return rows.map(_eventFromRow).toList();
  }

  @override
  Future<List<String>> seriesMemberIds(String calendarId, {String? recurringRemoteId, String? uid}) async {
    if (recurringRemoteId == null && uid == null) return const [];
    final rows = await _db.query('events',
        columns: ['id'],
        where: 'calendar_id = ? AND (recurring_remote_id = ? OR (remote_id = ? AND recurrence_id IS NOT NULL))',
        whereArgs: [calendarId, recurringRemoteId, uid]);
    return [for (final r in rows) r['id'] as String];
  }

  @override
  Future<List<CalendarEvent>> searchEvents(String query, Set<String> calendarIds,
      {int limit = 200}) async {
    if (calendarIds.isEmpty || query.trim().isEmpty) return const [];
    final like = '%${query.trim()}%';
    final placeholders = List.filled(calendarIds.length, '?').join(',');
    final rows = await _db.rawQuery('''
      SELECT * FROM events
      WHERE calendar_id IN ($placeholders)
        AND (title LIKE ? OR location LIKE ? OR description LIKE ?)
      ORDER BY start_ms
      LIMIT ?
    ''', [...calendarIds, like, like, like, limit]);
    return rows.map(_eventFromRow).toList();
  }

  static int _encodeDate(DateTime d, bool allDay) => allDay
      ? DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch
      : d.toUtc().millisecondsSinceEpoch;

  static DateTime _decodeDate(int ms, bool allDay) {
    if (!allDay) return DateTime.fromMillisecondsSinceEpoch(ms);
    final u = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return DateTime(u.year, u.month, u.day);
  }

  Map<String, Object?> _eventToRow(CalendarEvent e) => {
        'id': e.id,
        'calendar_id': e.calendarId,
        'remote_id': e.remoteId,
        'recurring_remote_id': e.recurringRemoteId,
        'title': e.title,
        'description': e.description,
        'location': e.location,
        'start_ms': _encodeDate(e.start, e.allDay),
        'end_ms': _encodeDate(e.end, e.allDay),
        'all_day': e.allDay ? 1 : 0,
        'time_zone': e.timeZone,
        'rrule': (e.rrule?.isEmpty ?? true) ? null : e.rrule,
        'exdates': e.exdates.isEmpty
            ? null
            : jsonEncode([for (final d in e.exdates) _encodeDate(d, e.allDay)]),
        'color': e.color?.toARGB32(),
        'href': e.href,
        'etag': e.etag,
        'recurrence_id':
            e.recurrenceId == null ? null : _encodeDate(e.recurrenceId!, e.allDay),
        'reminders': e.reminders.isEmpty ? null : Reminder.encodeList(e.reminders),
        'extra_alarms': e.extraAlarms.isEmpty ? null : jsonEncode(e.extraAlarms),
        'updated_at': e.updatedAt?.millisecondsSinceEpoch,
      };

  CalendarEvent _eventFromRow(Map<String, Object?> r) {
    final allDay = (r['all_day'] as int) == 1;
    final exJson = r['exdates'] as String?;
    return CalendarEvent(
      id: r['id'] as String,
      calendarId: r['calendar_id'] as String,
      remoteId: r['remote_id'] as String?,
      recurringRemoteId: r['recurring_remote_id'] as String?,
      title: r['title'] as String,
      description: r['description'] as String?,
      location: r['location'] as String?,
      start: _decodeDate(r['start_ms'] as int, allDay),
      end: _decodeDate(r['end_ms'] as int, allDay),
      allDay: allDay,
      timeZone: r['time_zone'] as String?,
      rrule: r['rrule'] as String?,
      exdates: exJson == null
          ? const []
          : [
              for (final v in (jsonDecode(exJson) as List).cast<int>())
                _decodeDate(v, allDay)
            ],
      color: r['color'] == null ? null : Color(r['color'] as int),
      href: r['href'] as String?,
      etag: r['etag'] as String?,
      recurrenceId: r['recurrence_id'] == null
          ? null
          : _decodeDate(r['recurrence_id'] as int, allDay),
      reminders: Reminder.decodeList(r['reminders'] as String?),
      extraAlarms: r['extra_alarms'] == null
          ? const []
          : (jsonDecode(r['extra_alarms'] as String) as List).cast<String>(),
      updatedAt: r['updated_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    );
  }
}
