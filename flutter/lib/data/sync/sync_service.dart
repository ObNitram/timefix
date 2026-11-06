import 'dart:ui' show Color;

import 'package:uuid/uuid.dart';

import '../../core/colors.dart';
import '../../core/time_zone.dart';
import '../../domain/models.dart';
import '../../domain/reminders.dart';
import '../caldav/caldav_client.dart';
import '../calendar_repository.dart';
import '../credentials.dart';
import '../google/google_calendar_service.dart';
import '../google/google_mapper.dart';
import '../ical/ical_service.dart';
import '../ical/ics_parser.dart';

typedef CalDavClientFactory = CalDavClient Function(String username, String password);

CalDavClient _defaultCalDavClient(String username, String password) =>
    CalDavClient(username: username, password: password);

const _uuid = Uuid();

/// Result of a synchronisation run.
class SyncReport {
  SyncReport(this.errors);

  /// Source id → error message.
  final Map<String, String> errors;
  bool get hasErrors => errors.isNotEmpty;
}

/// Pulls remote sources (iCal subscriptions, Google accounts) into the local
/// database and creates new sources.
class SyncService {
  SyncService({
    required this.repository,
    required this.ical,
    required this.google,
    CredentialStore? credentials,
    CalDavClientFactory? caldavClientFactory,
    this.googlePastWindow = const Duration(days: 180),
    this.googleFutureWindow = const Duration(days: 730),
  })  : credentials = credentials ?? InMemoryCredentialStore(),
        caldavClientFactory = caldavClientFactory ?? _defaultCalDavClient;

  final CalendarRepository repository;
  final IcalService ical;
  final GoogleCalendarGateway google;
  final CredentialStore credentials;
  final CalDavClientFactory caldavClientFactory;

  /// Default reminders of each Google calendar (from the calendar list).
  final Map<String, List<Reminder>> _googleDefaults = {};

  /// Google events are fetched in `[now - past, now + future]`.
  final Duration googlePastWindow;
  final Duration googleFutureWindow;

  // ---------------------------------------------------------------------------
  // Creating sources
  // ---------------------------------------------------------------------------

  /// Ensures a local source with one default calendar exists.
  Future<void> ensureLocalCalendar(String defaultName) async {
    final sources = await repository.getSources();
    if (sources.any((s) => s.type == SourceType.local)) return;
    const sourceId = 'local';
    await repository.upsertSource(
        CalendarSource(id: sourceId, type: SourceType.local, name: defaultName));
    await repository.upsertCalendar(CalendarInfo(
      id: 'local:default',
      sourceId: sourceId,
      name: defaultName,
      color: calendarPalette[6].color,
    ));
  }

  Future<CalendarInfo> addLocalCalendar(String name, Color color) async {
    final sources = await repository.getSources();
    var local = sources.where((s) => s.type == SourceType.local).firstOrNull;
    if (local == null) {
      local = const CalendarSource(id: 'local', type: SourceType.local, name: 'Local');
      await repository.upsertSource(local);
    }
    final cals = await repository.getCalendars();
    final cal = CalendarInfo(
      id: 'local:${_uuid.v4()}',
      sourceId: local.id,
      name: name,
      color: color,
      sortOrder: cals.length,
    );
    await repository.upsertCalendar(cal);
    return cal;
  }

  /// Subscribes to an iCal URL. Throws [IcalFetchException] if it cannot be
  /// downloaded or parsed; nothing is saved in that case.
  Future<CalendarSource> addIcalSubscription({
    required String url,
    String? name,
    required Color color,
  }) async {
    final normalized = IcalService.normalizeUrl(url).toString();
    final cal = await ical.fetch(normalized);
    final sourceId = 'ical:${_uuid.v4()}';
    final displayName = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : (cal.name ?? Uri.parse(normalized).host);
    final source = CalendarSource(
      id: sourceId,
      type: SourceType.ical,
      name: displayName,
      url: normalized,
      lastSyncedAt: DateTime.now(),
    );
    await repository.upsertSource(source);
    final calendarId = '$sourceId:main';
    final cals = await repository.getCalendars();
    await repository.upsertCalendar(CalendarInfo(
      id: calendarId,
      sourceId: sourceId,
      name: displayName,
      color: color,
      readOnly: true,
      sortOrder: cals.length,
    ));
    await repository.replaceEvents(calendarId, IcalService.toEvents(cal, calendarId));
    return source;
  }

  /// Signs in to Google and imports the account calendars.
  Future<CalendarSource> addGoogleAccount() async {
    final email = await google.signIn();
    final sourceId = 'google:$email';
    final source = CalendarSource(
      id: sourceId,
      type: SourceType.google,
      name: email,
      accountEmail: email,
    );
    await repository.upsertSource(source);
    await _syncGoogle(source, interactive: true);
    return (await repository.getSource(sourceId))!;
  }

  /// Connects to a CalDAV server, stores the password securely and imports
  /// the account's calendars. Nothing is saved if the connection fails.
  Future<CalendarSource> addCalDavAccount({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final client = caldavClientFactory(username.trim(), password);
    final account = await client.discover(serverUrl);
    final sourceId = 'caldav:${_uuid.v4()}';
    final source = CalendarSource(
      id: sourceId,
      type: SourceType.caldav,
      name: '${username.trim()}@${account.home.host}',
      url: account.home.toString(),
      username: username.trim(),
    );
    await credentials.write(CredentialStore.caldavPasswordKey(sourceId), password);
    await repository.upsertSource(source);
    await _syncCalDav(source, client: client, calendars: account.calendars);
    return (await repository.getSource(sourceId))!;
  }

  /// Client for a CalDAV source, using the stored password.
  Future<CalDavClient> calDavClientFor(CalendarSource source) async {
    final password = await credentials.read(CredentialStore.caldavPasswordKey(source.id));
    if (password == null || source.username == null) {
      throw CalDavAuthException();
    }
    return caldavClientFactory(source.username!, password);
  }

  /// Replaces the stored password after checking it against the server.
  Future<void> updateCalDavPassword(CalendarSource source, String password) async {
    final client = caldavClientFactory(source.username!, password);
    await client.listCalendars(Uri.parse(source.url!));
    await credentials.write(CredentialStore.caldavPasswordKey(source.id), password);
    await syncSource(source);
  }

  /// Creates a calendar on the CalDAV server (MKCALENDAR) and imports it.
  Future<void> createCalDavCalendar(CalendarSource source, String name, Color color) async {
    final client = await calDavClientFor(source);
    final slug = _uuid.v4();
    await client.makeCalendar(Uri.parse(source.url!), slug, name, color);
    await syncSource(source);
  }

  Future<void> removeSource(CalendarSource source) async {
    if (source.type == SourceType.caldav) {
      await credentials.delete(CredentialStore.caldavPasswordKey(source.id));
    }
    if (source.type == SourceType.google) {
      try {
        await google.signOut();
      } catch (_) {}
    }
    await repository.deleteSource(source.id);
  }

  // ---------------------------------------------------------------------------
  // Synchronisation
  // ---------------------------------------------------------------------------

  Future<SyncReport> syncAll({bool interactive = false}) async {
    final errors = <String, String>{};
    for (final s in await repository.getSources()) {
      if (!s.isRemote) continue;
      try {
        await syncSource(s, interactive: interactive);
      } catch (e) {
        errors[s.id] = e.toString();
      }
    }
    return SyncReport(errors);
  }

  Future<void> syncSource(CalendarSource source, {bool interactive = false}) async {
    try {
      switch (source.type) {
        case SourceType.local:
          return;
        case SourceType.ical:
          await _syncIcal(source);
        case SourceType.google:
          await _syncGoogle(source, interactive: interactive);
        case SourceType.caldav:
          await _syncCalDav(source);
      }
    } catch (e) {
      final current = await repository.getSource(source.id) ?? source;
      await repository.upsertSource(current.copyWith(lastError: e.toString()));
      rethrow;
    }
  }

  Future<void> _syncIcal(CalendarSource source) async {
    final cal = await ical.fetch(source.url!);
    final calendars = await repository.getCalendars();
    final calendarId = '${source.id}:main';
    if (!calendars.any((c) => c.id == calendarId)) {
      await repository.upsertCalendar(CalendarInfo(
        id: calendarId,
        sourceId: source.id,
        name: source.name,
        color: googleBlue,
        readOnly: true,
      ));
    }
    await repository.replaceEvents(calendarId, IcalService.toEvents(cal, calendarId));
    await repository.upsertSource(
        source.copyWith(lastSyncedAt: DateTime.now(), clearError: true));
  }

  Future<void> _syncCalDav(
    CalendarSource source, {
    CalDavClient? client,
    List<CalDavCalendar>? calendars,
  }) async {
    client ??= await calDavClientFor(source);
    calendars ??= await client.listCalendars(Uri.parse(source.url!));
    final existing = {
      for (final c in await repository.getCalendars())
        if (c.sourceId == source.id) c.remoteId: c
    };
    final seen = <String>{};
    var order = 200;
    for (final remote in calendars) {
      final remoteId = remote.url.toString();
      seen.add(remoteId);
      final old = existing[remoteId];
      final cal = CalendarInfo(
        id: old?.id ?? '${source.id}:$remoteId',
        sourceId: source.id,
        remoteId: remoteId,
        name: remote.displayName,
        color: old?.color ?? remote.color ?? calendarPalette[6].color,
        visible: old?.visible ?? true,
        readOnly: remote.readOnly,
        sortOrder: old?.sortOrder ?? order++,
        syncToken: old?.syncToken,
      );
      await repository.upsertCalendar(cal);
      // Only download calendars whose ctag changed.
      if (remote.ctag == null || remote.ctag != old?.syncToken) {
        await syncCalDavCalendar(cal, client: client, ctag: remote.ctag);
      }
    }
    for (final old in existing.values) {
      if (!seen.contains(old.remoteId)) await repository.deleteCalendar(old.id);
    }
    await repository.upsertSource(
        source.copyWith(lastSyncedAt: DateTime.now(), clearError: true));
  }

  /// Re-downloads all the events of one CalDAV calendar.
  Future<void> syncCalDavCalendar(CalendarInfo cal,
      {CalDavClient? client, String? ctag, CalendarSource? source}) async {
    if (client == null) {
      source ??= await repository.getSource(cal.sourceId);
      client = await calDavClientFor(source!);
    }
    final url = Uri.parse(cal.remoteId!);
    ctag ??= await client.ctag(url);
    final objects = await client.fetchEvents(url);
    final parser = IcsParser(defaultLocation: deviceTimeZoneName == null ? null : deviceLocation);
    final events = <CalendarEvent>[];
    for (final o in objects) {
      try {
        events.addAll(IcalService.toEvents(parser.parse(o.data), cal.id, includeReminders: true)
            .map((e) => e.copyWith(href: o.url.toString(), etag: o.etag)));
      } catch (_) {
        // Skip resources the parser cannot read.
      }
    }
    await repository.replaceEvents(cal.id, events);
    final current = await repository.getCalendar(cal.id) ?? cal;
    await repository.upsertCalendar(current.copyWith(syncToken: ctag));
  }

  Future<void> _syncGoogle(CalendarSource source, {required bool interactive}) async {
    final entries = await google.listCalendars(interactive: interactive);
    final existing = {
      for (final c in await repository.getCalendars())
        if (c.sourceId == source.id) c.remoteId: c
    };
    final seen = <String>{};
    var order = 100;
    for (final entry in entries) {
      final remoteId = entry.id;
      if (remoteId == null || (entry.deleted ?? false)) continue;
      seen.add(remoteId);
      final old = existing[remoteId];
      final readOnly = !(entry.accessRole == 'owner' || entry.accessRole == 'writer');
      final cal = CalendarInfo(
        id: old?.id ?? '${source.id}:$remoteId',
        sourceId: source.id,
        remoteId: remoteId,
        name: entry.summaryOverride ?? entry.summary ?? remoteId,
        // Keep the user's local choices for color and visibility.
        color: old?.color ?? parseHexColor(entry.backgroundColor),
        visible: old?.visible ?? (entry.selected ?? true),
        readOnly: readOnly,
        sortOrder: old?.sortOrder ?? (entry.primary == true ? 99 : order++),
      );
      await repository.upsertCalendar(cal);
      _googleDefaults[cal.id] = GoogleMapper.remindersFrom(entry.defaultReminders);
      await syncGoogleCalendar(cal, interactive: interactive);
    }
    for (final old in existing.values) {
      if (!seen.contains(old.remoteId)) await repository.deleteCalendar(old.id);
    }
    await repository.upsertSource(
        source.copyWith(lastSyncedAt: DateTime.now(), clearError: true));
  }

  /// Re-downloads the events of one Google calendar.
  Future<void> syncGoogleCalendar(CalendarInfo cal, {bool interactive = false}) async {
    if (!_googleDefaults.containsKey(cal.id)) {
      // Needed to resolve events using the calendar's default reminders.
      for (final entry in await google.listCalendars(interactive: interactive)) {
        if (entry.id == cal.remoteId) {
          _googleDefaults[cal.id] = GoogleMapper.remindersFrom(entry.defaultReminders);
        }
      }
    }
    final defaults = _googleDefaults[cal.id] ?? const <Reminder>[];
    final now = DateTime.now();
    final events = await google.listEvents(
      cal.remoteId!,
      now.subtract(googlePastWindow),
      now.add(googleFutureWindow),
      interactive: interactive,
    );
    final mapped = [
      for (final e in events) ?GoogleMapper.fromGoogle(e, cal.id, calendarDefaults: defaults),
    ];
    await repository.replaceEvents(cal.id, mapped);
  }
}
