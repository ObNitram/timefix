import 'package:uuid/uuid.dart';

import '../core/time_zone.dart';
import '../domain/models.dart';
import '../domain/recurrence.dart';
import 'calendar_repository.dart';
import 'google/google_calendar_service.dart';
import 'google/google_mapper.dart';
import 'sync/sync_service.dart';

const _uuid = Uuid();

/// Which occurrences of a recurring event an edit / deletion applies to.
enum RecurrenceScope { thisEvent, thisAndFollowing, all }

class ReadOnlyCalendarException implements Exception {
  @override
  String toString() => 'This calendar is read only';
}

/// Creates, updates and deletes events, writing to the remote service when the
/// calendar belongs to a Google account.
class EventService {
  EventService({
    required this.repository,
    required this.google,
    required this.sync,
  });

  final CalendarRepository repository;
  final GoogleCalendarGateway google;
  final SyncService sync;

  String newEventId() => 'local-event:${_uuid.v4()}';

  Future<(CalendarInfo, CalendarSource)> _calendarAndSource(String calendarId) async {
    final cal = await repository.getCalendar(calendarId);
    if (cal == null) throw StateError('Unknown calendar $calendarId');
    final source = await repository.getSource(cal.sourceId);
    if (source == null) throw StateError('Unknown source ${cal.sourceId}');
    return (cal, source);
  }

  /// Creates a new event.
  Future<void> create(CalendarEvent event) async {
    final (cal, source) = await _calendarAndSource(event.calendarId);
    if (cal.readOnly) throw ReadOnlyCalendarException();
    final e = event.copyWith(
      timeZone: event.timeZone ?? deviceTimeZoneName,
      updatedAt: DateTime.now(),
    );
    switch (source.type) {
      case SourceType.local:
        await repository.upsertEvent(e);
      case SourceType.google:
        final created =
            await google.insertEvent(cal.remoteId!, GoogleMapper.toGoogle(e));
        if (e.isRecurring) {
          await sync.syncGoogleCalendar(cal, interactive: true);
        } else {
          final mapped = GoogleMapper.fromGoogle(created, cal.id);
          if (mapped != null) await repository.upsertEvent(mapped);
        }
      case SourceType.ical:
        throw ReadOnlyCalendarException();
    }
  }

  /// Saves [edited], the new version of the occurrence [original] of
  /// [original.event].
  Future<void> update({
    required EventOccurrence original,
    required CalendarEvent edited,
    RecurrenceScope scope = RecurrenceScope.all,
  }) async {
    final master = original.event;
    final (oldCal, oldSource) = await _calendarAndSource(master.calendarId);
    if (oldCal.readOnly) throw ReadOnlyCalendarException();

    // Moving to another calendar: create there, delete here.
    if (edited.calendarId != master.calendarId) {
      final (newCal, newSource) = await _calendarAndSource(edited.calendarId);
      if (newCal.readOnly) throw ReadOnlyCalendarException();
      if (oldSource.type == SourceType.local && newSource.type == SourceType.local) {
        await _updateLocal(original, edited, scope);
        return;
      }
      await create(edited.copyWith(id: newEventId()));
      await delete(original, scope: scope);
      return;
    }

    switch (oldSource.type) {
      case SourceType.local:
        await _updateLocal(original, edited, scope);
      case SourceType.google:
        // Google instances are stored individually: edit this one only.
        await google.patchEvent(oldCal.remoteId!, master.remoteId!,
            GoogleMapper.toGoogle(edited, includeRecurrence: !master.isPartOfSeries));
        await sync.syncGoogleCalendar(oldCal, interactive: true);
      case SourceType.ical:
        throw ReadOnlyCalendarException();
    }
  }

  Future<void> _updateLocal(
      EventOccurrence original, CalendarEvent edited, RecurrenceScope scope) async {
    final master = original.event;
    final now = DateTime.now();
    if (!master.isRecurring) {
      await repository.upsertEvent(edited.copyWith(id: master.id, updatedAt: now));
      return;
    }
    final isFirst = original.start == master.start;
    switch (scope) {
      case RecurrenceScope.thisEvent:
        await repository.upsertEvent(master.copyWith(
            exdates: [...master.exdates, original.start], updatedAt: now));
        await repository.upsertEvent(edited.copyWith(
            id: newEventId(), clearRrule: true, exdates: const [], updatedAt: now));
      case RecurrenceScope.thisAndFollowing when !isFirst:
        await repository.upsertEvent(master.copyWith(
            rrule: rruleEndingBefore(master.rrule!, original.start, master.allDay),
            updatedAt: now));
        await repository.upsertEvent(edited.copyWith(
            id: newEventId(), exdates: const [], updatedAt: now));
      case RecurrenceScope.thisAndFollowing:
      case RecurrenceScope.all:
        // Shift the series by the same amount the occurrence was moved.
        final shift = edited.start.difference(original.start);
        final duration = edited.end.difference(edited.start);
        final newStart = master.start.add(shift);
        await repository.upsertEvent(edited.copyWith(
          id: master.id,
          start: newStart,
          end: newStart.add(duration),
          exdates: shift == Duration.zero ? master.exdates : const [],
          updatedAt: now,
        ));
    }
  }

  Future<void> delete(EventOccurrence occurrence,
      {RecurrenceScope scope = RecurrenceScope.all}) async {
    final master = occurrence.event;
    final (cal, source) = await _calendarAndSource(master.calendarId);
    if (cal.readOnly) throw ReadOnlyCalendarException();
    switch (source.type) {
      case SourceType.local:
        if (!master.isRecurring || scope == RecurrenceScope.all) {
          await repository.deleteEvent(master.id);
        } else if (scope == RecurrenceScope.thisEvent) {
          await repository.upsertEvent(master.copyWith(
              exdates: [...master.exdates, occurrence.start],
              updatedAt: DateTime.now()));
        } else if (occurrence.start == master.start) {
          await repository.deleteEvent(master.id);
        } else {
          await repository.upsertEvent(master.copyWith(
              rrule: rruleEndingBefore(master.rrule!, occurrence.start, master.allDay),
              updatedAt: DateTime.now()));
        }
      case SourceType.google:
        final id = scope == RecurrenceScope.all && master.recurringRemoteId != null
            ? master.recurringRemoteId!
            : master.remoteId!;
        await google.deleteEvent(cal.remoteId!, id);
        if (id == master.remoteId) {
          await repository.deleteEvent(master.id);
        } else {
          await sync.syncGoogleCalendar(cal, interactive: true);
        }
      case SourceType.ical:
        throw ReadOnlyCalendarException();
    }
  }
}
