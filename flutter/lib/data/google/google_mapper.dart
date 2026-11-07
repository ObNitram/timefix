import 'package:googleapis/calendar/v3.dart' as gcal;

import '../../core/colors.dart';
import '../../core/time_zone.dart';
import '../../domain/models.dart';
import '../../domain/reminders.dart';

/// Conversions between Google Calendar API objects and app models.
class GoogleMapper {
  static String eventId(String calendarId, String remoteId) =>
      '$calendarId|$remoteId';

  /// Google only stores "popup" reminders in minutes before the start, at
  /// most 5 per event, up to 4 weeks.
  static bool isGoogleReminder(Reminder r) =>
      r.type == ReminderType.push && r.minutesBefore >= 0 && r.minutesBefore <= maxReminderMinutes;

  static List<Reminder> remindersFrom(List<gcal.EventReminder>? reminders) => Reminder.normalize([
        for (final r in reminders ?? const <gcal.EventReminder>[])
          if (r.method == 'popup' && r.minutes != null) Reminder(r.minutes!, ReminderType.push),
      ]);

  /// Returns null for cancelled events or events without dates.
  /// [calendarDefaults] are the calendar's default reminders, used when the
  /// event says `useDefault`.
  static CalendarEvent? fromGoogle(gcal.Event e, String calendarId,
      {List<Reminder> calendarDefaults = const []}) {
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
      // The calendar defaults returned by the API are those of timed events;
      // all-day defaults are not exposed.
      reminders: (e.reminders?.useDefault ?? false)
          ? (allDay ? const <Reminder>[] : calendarDefaults)
          : remindersFrom(e.reminders?.overrides),
      updatedAt: e.updated?.toLocal(),
    );
  }

  /// The part of [reminders] Google stores (popups, at most 5).
  static List<Reminder> googlePart(List<Reminder> reminders) =>
      Reminder.normalize(reminders.where(isGoogleReminder)).take(5).toList();

  static bool sameGoogleReminders(List<Reminder> a, List<Reminder> b) {
    final x = googlePart(a), y = googlePart(b);
    return x.length == y.length && [for (var i = 0; i < x.length; i++) x[i] == y[i]].every((v) => v);
  }

  /// [includeReminders]: false leaves the event's reminders untouched on the
  /// server (a PATCH replaces the whole reminders object, including e-mail
  /// reminders TimeFix does not know). [calendarDefaults] lets an event that
  /// uses exactly the calendar defaults keep `useDefault`.
  static gcal.Event toGoogle(CalendarEvent e,
      {bool includeRecurrence = true, bool includeReminders = true, List<Reminder>? calendarDefaults}) {
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
    if (includeReminders) {
      final popups = googlePart(e.reminders);
      final useDefault = !e.allDay &&
          calendarDefaults != null &&
          calendarDefaults.isNotEmpty &&
          sameGoogleReminders(popups, calendarDefaults);
      event.reminders = useDefault
          ? gcal.EventReminders(useDefault: true)
          : gcal.EventReminders(useDefault: false, overrides: [
              for (final r in popups) gcal.EventReminder(method: 'popup', minutes: r.minutesBefore),
            ]);
    }
    return event;
  }
}
