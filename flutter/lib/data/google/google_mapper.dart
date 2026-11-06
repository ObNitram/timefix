import 'package:googleapis/calendar/v3.dart' as gcal;

import '../../core/colors.dart';
import '../../core/time_zone.dart';
import '../../domain/models.dart';

/// Conversions between Google Calendar API objects and app models.
class GoogleMapper {
  static String eventId(String calendarId, String remoteId) =>
      '$calendarId|$remoteId';

  /// Returns null for cancelled events or events without dates.
  static CalendarEvent? fromGoogle(gcal.Event e, String calendarId) {
    if (e.status == 'cancelled' || e.id == null) return null;
    final s = e.start, en = e.end;
    if (s == null) return null;
    final allDay = s.date != null;
    DateTime start, end;
    if (allDay) {
      start = DateTime(s.date!.year, s.date!.month, s.date!.day);
      final ed = en?.date;
      end = ed == null
          ? DateTime(start.year, start.month, start.day + 1)
          : DateTime(ed.year, ed.month, ed.day);
    } else {
      if (s.dateTime == null) return null;
      start = s.dateTime!.toLocal();
      end = (en?.dateTime ?? s.dateTime!).toLocal();
    }
    String? rrule;
    for (final r in e.recurrence ?? const <String>[]) {
      if (r.toUpperCase().startsWith('RRULE:')) rrule = r.substring(6);
    }
    return CalendarEvent(
      id: eventId(calendarId, e.id!),
      calendarId: calendarId,
      remoteId: e.id,
      recurringRemoteId: e.recurringEventId,
      title: e.summary ?? '',
      description: e.description,
      location: e.location,
      start: start,
      end: end,
      allDay: allDay,
      timeZone: s.timeZone,
      // With singleEvents=true the API returns expanded instances, so masters
      // are never stored. The rule is kept only when present.
      rrule: rrule,
      color: colorForGoogleEventColorId(e.colorId),
      updatedAt: e.updated?.toLocal(),
    );
  }

  static gcal.Event toGoogle(CalendarEvent e, {bool includeRecurrence = true}) {
    final tzName = e.timeZone ?? deviceTimeZoneName ?? 'UTC';
    final event = gcal.Event()
      ..summary = e.title
      ..description = e.description ?? ''
      ..location = e.location ?? ''
      ..colorId = e.color == null ? null : googleEventColorIdFor(e.color!);
    if (e.allDay) {
      event.start = gcal.EventDateTime(
          date: DateTime.utc(e.start.year, e.start.month, e.start.day));
      event.end =
          gcal.EventDateTime(date: DateTime.utc(e.end.year, e.end.month, e.end.day));
    } else {
      event.start = gcal.EventDateTime(dateTime: e.start.toUtc(), timeZone: tzName);
      event.end = gcal.EventDateTime(dateTime: e.end.toUtc(), timeZone: tzName);
    }
    if (includeRecurrence && e.isRecurring) {
      event.recurrence = ['RRULE:${e.rrule}'];
    }
    return event;
  }
}
