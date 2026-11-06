import '../core/date_utils.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';

/// Persistence of sources, calendars and events.
abstract class CalendarRepository {
  Future<List<CalendarSource>> getSources();
  Future<CalendarSource?> getSource(String id);
  Future<void> upsertSource(CalendarSource source);

  /// Deletes the source with all its calendars and events.
  Future<void> deleteSource(String id);

  Future<List<CalendarInfo>> getCalendars();
  Future<CalendarInfo?> getCalendar(String id);
  Future<void> upsertCalendar(CalendarInfo calendar);
  Future<void> deleteCalendar(String id);

  /// Events that may have an occurrence within [range]: non-recurring events
  /// overlapping it, and recurring masters starting before its end.
  /// Results may include a few events slightly outside the range; callers must
  /// filter through the recurrence expander.
  Future<List<CalendarEvent>> eventsForRange(
      DateRange range, Set<String> calendarIds);

  Future<CalendarEvent?> getEvent(String id);
  Future<void> upsertEvent(CalendarEvent event);
  Future<void> deleteEvent(String id);

  /// Replaces every event of [calendarId] (used by synchronisation).
  Future<void> replaceEvents(String calendarId, List<CalendarEvent> events);

  /// Events stored in the CalDAV resource [href] (a series and its overrides).
  Future<List<CalendarEvent>> eventsByHref(String calendarId, String href);

  /// Reminders kept on this device only, by event id (all of them when
  /// [eventIds] is null).
  Future<Map<String, List<Reminder>>> localReminders([Set<String>? eventIds]);

  /// Replaces the device-only reminders of an event (empty list removes them).
  Future<void> setLocalReminders(String eventId, List<Reminder> reminders);

  /// Events whose title, location or description contains [query].
  Future<List<CalendarEvent>> searchEvents(String query, Set<String> calendarIds,
      {int limit = 200});
}

/// Simple in-memory implementation, used for tests and previews.
class InMemoryCalendarRepository implements CalendarRepository {
  final Map<String, CalendarSource> _sources = {};
  final Map<String, CalendarInfo> _calendars = {};
  final Map<String, CalendarEvent> _events = {};
  final Map<String, List<Reminder>> _localReminders = {};

  @override
  Future<Map<String, List<Reminder>>> localReminders([Set<String>? eventIds]) async => {
        for (final e in _localReminders.entries)
          if (eventIds == null || eventIds.contains(e.key)) e.key: e.value,
      };

  @override
  Future<void> setLocalReminders(String eventId, List<Reminder> reminders) async {
    if (reminders.isEmpty) {
      _localReminders.remove(eventId);
    } else {
      _localReminders[eventId] = List.unmodifiable(reminders);
    }
  }

  @override
  Future<List<CalendarSource>> getSources() async => _sources.values.toList();

  @override
  Future<CalendarSource?> getSource(String id) async => _sources[id];

  @override
  Future<void> upsertSource(CalendarSource source) async =>
      _sources[source.id] = source;

  @override
  Future<void> deleteSource(String id) async {
    _sources.remove(id);
    final cals =
        _calendars.values.where((c) => c.sourceId == id).map((c) => c.id).toList();
    for (final c in cals) {
      await deleteCalendar(c);
    }
  }

  @override
  Future<List<CalendarInfo>> getCalendars() async {
    final list = _calendars.values.toList()
      ..sort((a, b) => a.sortOrder != b.sortOrder
          ? a.sortOrder.compareTo(b.sortOrder)
          : a.name.compareTo(b.name));
    return list;
  }

  @override
  Future<CalendarInfo?> getCalendar(String id) async => _calendars[id];

  @override
  Future<void> upsertCalendar(CalendarInfo calendar) async =>
      _calendars[calendar.id] = calendar;

  @override
  Future<void> deleteCalendar(String id) async {
    _calendars.remove(id);
    _events.removeWhere((_, e) => e.calendarId == id);
  }

  @override
  Future<List<CalendarEvent>> eventsForRange(
      DateRange range, Set<String> calendarIds) async {
    final slackStart = addDays(range.start, -1);
    final slackEnd = addDays(range.end, 1);
    return _events.values.where((e) {
      if (!calendarIds.contains(e.calendarId)) return false;
      if (e.isRecurring) return e.start.isBefore(slackEnd);
      return e.start.isBefore(slackEnd) && !e.end.isBefore(slackStart);
    }).toList();
  }

  @override
  Future<CalendarEvent?> getEvent(String id) async => _events[id];

  @override
  Future<void> upsertEvent(CalendarEvent event) async => _events[event.id] = event;

  @override
  Future<void> deleteEvent(String id) async => _events.remove(id);

  @override
  Future<void> replaceEvents(String calendarId, List<CalendarEvent> events) async {
    _events.removeWhere((_, e) => e.calendarId == calendarId);
    for (final e in events) {
      _events[e.id] = e;
    }
  }

  @override
  Future<List<CalendarEvent>> eventsByHref(String calendarId, String href) async =>
      _events.values.where((e) => e.calendarId == calendarId && e.href == href).toList();

  @override
  Future<List<CalendarEvent>> searchEvents(String query, Set<String> calendarIds,
      {int limit = 200}) async {
    final q = query.toLowerCase();
    return _events.values
        .where((e) =>
            calendarIds.contains(e.calendarId) &&
            (e.title.toLowerCase().contains(q) ||
                (e.location?.toLowerCase().contains(q) ?? false) ||
                (e.description?.toLowerCase().contains(q) ?? false)))
        .take(limit)
        .toList();
  }
}
