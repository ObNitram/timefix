import 'models.dart';
import 'reminders.dart';

/// One alert to schedule on the device.
class PlannedReminder {
  PlannedReminder({required this.occurrence, required this.reminder})
      : fireAt = reminder.fireTime(occurrence.start, allDay: occurrence.allDay);

  final EventOccurrence occurrence;
  final Reminder reminder;
  final DateTime fireAt;

  ReminderType get type => reminder.type;

  /// Identifies the alert across reschedulings.
  String get key =>
      '${occurrence.event.id}@${occurrence.start.millisecondsSinceEpoch}#${reminder.minutesBefore}:${reminder.type.name}';

  /// Positive 31-bit notification id derived from [key] (FNV-1a).
  int get notificationId => stableNotificationId(key);

  /// Changes when the alert's content changes (title, time, location…), so
  /// that scheduled notifications are refreshed.
  String get signature => [
        key,
        fireAt.millisecondsSinceEpoch,
        occurrence.event.title,
        occurrence.event.location ?? '',
        occurrence.end.millisecondsSinceEpoch,
      ].join('|');
}

int stableNotificationId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  // Keep away from 0 and from the ids reserved for test / snooze alerts.
  return (hash & 0x7FFFFFFF) | 0x1000;
}

/// Computes the alerts firing in `(now, until]`, earliest first, keeping at
/// most [maxCount] (iOS only keeps 64 pending notifications per app).
List<PlannedReminder> planReminders({
  required Iterable<EventOccurrence> occurrences,
  required Map<String, List<Reminder>> localReminders,
  required DateTime now,
  required DateTime until,
  int? maxCount,
}) {
  final planned = <PlannedReminder>[];
  final seen = <String>{};
  for (final o in occurrences) {
    for (final r in effectiveReminders(o.event, localReminders)) {
      final p = PlannedReminder(occurrence: o, reminder: r);
      if (!p.fireAt.isAfter(now) || p.fireAt.isAfter(until)) continue;
      if (seen.add(p.key)) planned.add(p);
    }
  }
  planned.sort((a, b) {
    final c = a.fireAt.compareTo(b.fireAt);
    // Alarms first when several alerts fire at the same time.
    return c != 0 ? c : b.type.index.compareTo(a.type.index);
  });
  return maxCount == null || planned.length <= maxCount ? planned : planned.sublist(0, maxCount);
}
