import '../core/date_utils.dart';
import 'models.dart';
import 'recurrence.dart';

const _expander = RecurrenceExpander();

/// Occurrences of [events] overlapping [range], sorted with
/// [compareOccurrences]. Events of calendars missing from [calendars] are
/// skipped.
List<EventOccurrence> expandEvents(
  Iterable<CalendarEvent> events,
  Map<String, CalendarInfo> calendars,
  DateRange range,
) {
  final result = <EventOccurrence>[];
  for (final e in events) {
    final cal = calendars[e.calendarId];
    if (cal == null) continue;
    for (final (start, end) in _expander.occurrences(e, range)) {
      result.add(EventOccurrence(event: e, start: start, end: end, color: e.color ?? cal.color));
    }
  }
  result.sort(compareOccurrences);
  return result;
}

/// Sort order used everywhere: by day, all-day events first, then by start
/// time, longest first, then by title.
int compareOccurrences(EventOccurrence a, EventOccurrence b) {
  final day = dateOnly(a.start).compareTo(dateOnly(b.start));
  if (day != 0) return day;
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  final s = a.start.compareTo(b.start);
  if (s != 0) return s;
  final d = b.end.compareTo(a.end);
  if (d != 0) return d;
  return a.title.compareTo(b.title);
}
