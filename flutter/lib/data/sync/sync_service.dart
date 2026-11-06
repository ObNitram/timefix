import 'dart:ui' show Color;

import 'package:uuid/uuid.dart';

import '../../core/colors.dart';
import '../../domain/models.dart';
import '../calendar_repository.dart';
import '../google/google_calendar_service.dart';
import '../google/google_mapper.dart';
import '../ical/ical_service.dart';

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
    this.googlePastWindow = const Duration(days: 180),
    this.googleFutureWindow = const Duration(days: 730),
  });

  final CalendarRepository repository;
  final IcalService ical;
  final GoogleCalendarGateway google;

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

  Future<void> removeSource(CalendarSource source) async {
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
    final now = DateTime.now();
    final events = await google.listEvents(
      cal.remoteId!,
      now.subtract(googlePastWindow),
      now.add(googleFutureWindow),
      interactive: interactive,
    );
    final mapped = [
      for (final e in events) ?GoogleMapper.fromGoogle(e, cal.id),
    ];
    await repository.replaceEvents(cal.id, mapped);
  }
}
