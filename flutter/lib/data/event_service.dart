import 'package:flutter/foundation.dart' show listEquals;
import 'package:uuid/uuid.dart';

import '../core/time_zone.dart';
import 'caldav/caldav_event_writer.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';
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
  }) : _caldav = CalDavEventWriter(repository: repository, sync: sync);

  final CalendarRepository repository;
  final GoogleCalendarGateway google;
  final SyncService sync;
  final CalDavEventWriter _caldav;

  String newEventId() => 'local-event:${_uuid.v4()}';

  Future<(CalendarInfo, CalendarSource)> _calendarAndSource(String calendarId) async {
    final cal = await repository.getCalendar(calendarId);
    if (cal == null) throw StateError('Unknown calendar $calendarId');
    final source = await repository.getSource(cal.sourceId);
    if (source == null) throw StateError('Unknown source ${cal.sourceId}');
    return (cal, source);
  }

  /// Google keeps "popup" reminders; full-screen and alarm reminders (and
  /// delays Google cannot express) stay on the device.
  static ({List<Reminder> synced, List<Reminder> local}) splitGoogleReminders(
      List<Reminder> reminders) {
    final synced = GoogleMapper.googlePart(reminders);
    return (synced: synced, local: Reminder.normalize(reminders.where((r) => !synced.contains(r))));
  }

  /// Saves reminders that cannot be stored with the event on this device.
  /// Local and CalDAV events keep all their reminders, so any leftover is
  /// cleared.
  Future<void> _storeLocalReminders(CalendarEvent stored, SourceType type, List<Reminder> all) async {
    final local = type == SourceType.google ? splitGoogleReminders(all).local : const <Reminder>[];
    await repository.setLocalReminders(localReminderKey(stored), local);
  }

  /// Stores [reminders] as the reminders kept on this device for [event].
  /// For a member of a series (Google instance, modified occurrence),
  /// [wholeSeries] applies them to every occurrence (occurrences with their
  /// own list follow again); otherwise to this occurrence only, where an
  /// empty list then means "none" rather than "same as the series".
  Future<void> setDeviceReminders(CalendarEvent event, List<Reminder> reminders,
      {bool wholeSeries = false}) async {
    final keys = deviceReminderKeys(event);
    final list = Reminder.normalize(reminders);
    if (keys.length == 1) {
      await repository.setLocalReminders(keys.single, list);
    } else if (!wholeSeries) {
      await repository.setLocalReminders(event.id, list, keepEmpty: true);
    } else {
      await repository.setLocalReminders(keys[1], list);
      final members = await repository.seriesMemberIds(event.calendarId,
          recurringRemoteId: event.recurringRemoteId,
          uid: event.recurrenceId != null ? event.remoteId : null);
      for (final id in {event.id, ...members}) {
        await repository.setLocalReminders(id, const []);
      }
    }
  }

  /// Creates a new event.
  Future<void> create(CalendarEvent event) async {
    final (cal, source) = await _calendarAndSource(event.calendarId);
    if (cal.readOnly) throw ReadOnlyCalendarException();
    final e = event.copyWith(
      timeZone: event.timeZone ?? deviceTimeZoneName,
      reminders: Reminder.normalize(event.reminders),
      updatedAt: DateTime.now(),
    );
    switch (source.type) {
      case SourceType.local:
        await repository.upsertEvent(e);
      case SourceType.google:
        final created = await google.insertEvent(cal.remoteId!,
            GoogleMapper.toGoogle(e, calendarDefaults: sync.googleDefaults(cal.id)));
        final key = e.isRecurring
            ? localReminderKey(e.copyWith(calendarId: cal.id, recurringRemoteId: created.id))
            : GoogleMapper.eventId(cal.id, created.id!);
        await repository.setLocalReminders(key, splitGoogleReminders(e.reminders).local);
        if (e.isRecurring) {
          await sync.syncGoogleCalendar(cal, interactive: true);
        } else {
          final mapped = GoogleMapper.fromGoogle(created, cal.id);
          if (mapped != null) await repository.upsertEvent(mapped);
        }
      case SourceType.caldav:
        await _caldav.create(e, cal, source);
      case SourceType.ical:
        throw ReadOnlyCalendarException();
    }
  }

  /// Saves [edited], the new version of the occurrence [original] of
  /// [original.event].
  ///
  /// For a Google instance (edited alone on Google), [deviceScope] says
  /// whether a change of the reminders kept on this device applies to this
  /// occurrence ([RecurrenceScope.thisEvent], the default) or to the series.
  Future<void> update({
    required EventOccurrence original,
    required CalendarEvent edited,
    RecurrenceScope scope = RecurrenceScope.all,
    RecurrenceScope? deviceScope,
  }) async {
    final master = original.event;
    final (oldCal, oldSource) = await _calendarAndSource(master.calendarId);
    if (oldCal.readOnly) throw ReadOnlyCalendarException();
    edited = edited.copyWith(reminders: Reminder.normalize(edited.reminders));

    // Moving to another calendar: create there, delete here.
    if (edited.calendarId != master.calendarId) {
      final (newCal, newSource) = await _calendarAndSource(edited.calendarId);
      if (newCal.readOnly) throw ReadOnlyCalendarException();
      if (oldSource.type == SourceType.local && newSource.type == SourceType.local) {
        await _updateLocal(original, edited, scope);
        return;
      }
      await create(edited.copyWith(id: newEventId()));
      // A Google instance is moved alone: never delete its whole series.
      await delete(original,
          scope: master.recurringRemoteId != null ? RecurrenceScope.thisEvent : scope);
      return;
    }

    switch (oldSource.type) {
      case SourceType.local:
        await _updateLocal(original, edited, scope);
        await _storeLocalReminders(master, oldSource.type, edited.reminders);
      case SourceType.google:
        // Google instances are stored individually: edit this one only.
        // Reminders are sent only when their Google part changed, so that
        // e-mail reminders and `useDefault` are left alone otherwise.
        await google.patchEvent(
            oldCal.remoteId!,
            master.remoteId!,
            GoogleMapper.toGoogle(
              edited,
              includeRecurrence: !master.isPartOfSeries,
              includeReminders: !GoogleMapper.sameGoogleReminders(edited.reminders, master.reminders),
              calendarDefaults: sync.googleDefaults(oldCal.id),
            ));
        final local = splitGoogleReminders(edited.reminders).local;
        if (master.recurringRemoteId != null) {
          // Written only when changed: an occurrence's own entry would hide
          // later changes made for the whole series.
          final stored = await repository.localReminders(deviceReminderKeys(master).toSet());
          final current = Reminder.normalize(deviceReminders(master, stored));
          if (deviceScope != null || !listEquals(current, local)) {
            await setDeviceReminders(master, local, wholeSeries: deviceScope == RecurrenceScope.all);
          }
        } else if (edited.isRecurring && !master.isPartOfSeries) {
          // A single event becomes a series: instances use the series key.
          await repository.setLocalReminders(master.id, const []);
          await repository.setLocalReminders('${oldCal.id}|series|${master.remoteId}', local);
        } else {
          await repository.setLocalReminders(localReminderKey(master), local);
        }
        await sync.syncGoogleCalendar(oldCal, interactive: true);
      case SourceType.caldav:
        await _caldav.update(original, edited, scope, oldCal, oldSource);
        await _storeLocalReminders(master, oldSource.type, edited.reminders);
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
          await repository.setLocalReminders(master.id, const []);
        } else {
          await repository.setLocalReminders(localReminderKey(master), const []);
          await sync.syncGoogleCalendar(cal, interactive: true);
        }
      case SourceType.caldav:
        await _caldav.delete(occurrence, scope, cal, source);
      case SourceType.ical:
        throw ReadOnlyCalendarException();
    }
  }
}
