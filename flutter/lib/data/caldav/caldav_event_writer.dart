import 'package:uuid/uuid.dart';

import '../../domain/models.dart';
import '../../domain/recurrence.dart';
import '../calendar_repository.dart';
import '../event_service.dart';
import '../ical/ics_writer.dart';
import '../sync/sync_service.dart';
import 'caldav_client.dart';

const _uuid = Uuid();

/// Applies event changes to a CalDAV calendar.
///
/// A CalDAV resource (.ics) holds one event, or a recurring event together
/// with its modified occurrences (same UID, RECURRENCE-ID). Every change
/// rewrites the whole resource with an `If-Match` precondition, so edits made
/// elsewhere in the meantime are detected (HTTP 412) instead of overwritten.
class CalDavEventWriter {
  CalDavEventWriter({required this.repository, required this.sync});

  final CalendarRepository repository;
  final SyncService sync;

  Future<void> create(CalendarEvent event, CalendarInfo cal, CalendarSource source) async {
    final uid = _uuid.v4();
    final href = Uri.parse(cal.remoteId!).resolve('$uid.ics').toString();
    final e = event.copyWith(
      id: '${cal.id}|$uid',
      calendarId: cal.id,
      remoteId: uid,
      href: href,
      clearRecurrenceId: true,
      updatedAt: DateTime.now(),
    );
    await _write(cal, source, href, before: const [], after: [e], create: true);
  }

  Future<void> update(EventOccurrence original, CalendarEvent edited, RecurrenceScope scope,
      CalendarInfo cal, CalendarSource source) async {
    final master = original.event;
    final href = master.href;
    if (href == null) throw CalDavException('Missing resource URL');
    final resource = await repository.eventsByHref(cal.id, href);
    final now = DateTime.now();
    final others = resource.where((e) => e.id != master.id).toList();

    CalendarEvent keepIdentity(CalendarEvent e) => e.copyWith(
          id: master.id,
          calendarId: cal.id,
          remoteId: master.remoteId,
          href: href,
          etag: master.etag,
          updatedAt: now,
        );

    if (!master.isRecurring) {
      // Plain event, or one modified occurrence of a series.
      var updated = keepIdentity(edited);
      if (master.recurrenceId != null) {
        updated = updated.copyWith(recurrenceId: master.recurrenceId, clearRrule: true);
      }
      await _write(cal, source, href, before: resource, after: [...others, updated]);
      return;
    }

    final isFirst = original.start == master.start;
    switch (scope) {
      case RecurrenceScope.thisEvent:
        // Add an override (RECURRENCE-ID) to the series.
        final override = edited.copyWith(
          id: '${cal.id}|${master.remoteId}|${original.start.millisecondsSinceEpoch}',
          calendarId: cal.id,
          remoteId: master.remoteId,
          href: href,
          recurrenceId: original.start,
          clearRrule: true,
          exdates: const [],
          updatedAt: now,
        );
        final newMaster = master.copyWith(exdates: [...master.exdates, original.start], updatedAt: now);
        await _write(cal, source, href, before: resource, after: [...others, newMaster, override]);
      case RecurrenceScope.thisAndFollowing when !isFirst:
        final ended = master.copyWith(
            rrule: rruleEndingBefore(master.rrule!, original.start, master.allDay), updatedAt: now);
        await _write(cal, source, href, before: resource, after: [...others, ended]);
        await create(edited.copyWith(exdates: const []), cal, source);
      case RecurrenceScope.thisAndFollowing:
      case RecurrenceScope.all:
        final shift = edited.start.difference(original.start);
        final duration = edited.end.difference(edited.start);
        final newStart = master.start.add(shift);
        final updated = keepIdentity(edited).copyWith(
          start: newStart,
          end: newStart.add(duration),
          exdates: shift == Duration.zero ? master.exdates : const [],
          clearRecurrenceId: true,
        );
        // Moving the whole series invalidates its modified occurrences.
        await _write(cal, source, href,
            before: resource, after: shift == Duration.zero ? [...others, updated] : [updated]);
    }
  }

  Future<void> delete(EventOccurrence occurrence, RecurrenceScope scope, CalendarInfo cal,
      CalendarSource source) async {
    final event = occurrence.event;
    final href = event.href;
    if (href == null) throw CalDavException('Missing resource URL');
    final resource = await repository.eventsByHref(cal.id, href);
    final now = DateTime.now();

    if (event.recurrenceId != null) {
      // Removing a modified occurrence: the master keeps it excluded.
      final remaining = <CalendarEvent>[];
      for (final e in resource) {
        if (e.id == event.id) continue;
        if (e.recurrenceId == null && e.isRecurring &&
            !e.exdates.any((x) => x.isAtSameMomentAs(event.recurrenceId!))) {
          remaining.add(e.copyWith(exdates: [...e.exdates, event.recurrenceId!], updatedAt: now));
        } else {
          remaining.add(e);
        }
      }
      await _write(cal, source, href, before: resource, after: remaining);
      return;
    }

    final isFirst = occurrence.start == event.start;
    final deleteAll = !event.isRecurring ||
        scope == RecurrenceScope.all ||
        (scope == RecurrenceScope.thisAndFollowing && isFirst);
    if (deleteAll) {
      await _write(cal, source, href, before: resource, after: const []);
      return;
    }
    final others = resource.where((e) => e.id != event.id).toList();
    final updated = scope == RecurrenceScope.thisEvent
        ? event.copyWith(exdates: [...event.exdates, occurrence.start], updatedAt: now)
        : event.copyWith(
            rrule: rruleEndingBefore(event.rrule!, occurrence.start, event.allDay), updatedAt: now);
    await _write(cal, source, href, before: resource, after: [...others, updated]);
  }

  /// Writes [after] as the content of [href] (or deletes it when empty), then
  /// mirrors the result in the local database.
  Future<void> _write(
    CalendarInfo cal,
    CalendarSource source,
    String href, {
    required List<CalendarEvent> before,
    required List<CalendarEvent> after,
    bool create = false,
  }) async {
    final client = await sync.calDavClientFor(source);
    final url = Uri.parse(href);
    final etag = before.map((e) => e.etag).nonNulls.firstOrNull;
    String? newEtag;
    try {
      if (after.isEmpty) {
        await client.delete(url, ifMatch: etag);
      } else {
        newEtag = await client.put(url, IcsWriter.resource(after), ifMatch: etag, create: create);
      }
    } on CalDavConflictException {
      // Someone else changed the event: refresh local data, then report.
      await sync.syncCalDavCalendar(cal, client: client);
      rethrow;
    }

    final keep = after.map((e) => e.id).toSet();
    for (final e in before) {
      if (!keep.contains(e.id)) await repository.deleteEvent(e.id);
    }
    for (final e in after) {
      await repository.upsertEvent(e.copyWith(etag: newEtag));
    }
    if (after.isNotEmpty && newEtag == null) {
      // The server did not return the new ETag (it may have rewritten the
      // data): download the calendar again to stay consistent.
      await sync.syncCalDavCalendar(cal, client: client);
    }
  }
}
