/// Event reminders: a delay relative to the start of the event and a way to
/// alert the user.
library;

import 'dart:convert';

/// How a reminder alerts the user.
enum ReminderType {
  /// Standard notification.
  push,

  /// Full-screen notification (Android full-screen intent; on iOS a Time
  /// Sensitive notification).
  fullScreen,

  /// Alarm clock: ringing screen with looping sound until stopped.
  alarm;

  /// Value written in iCalendar (X-TIMEFIX-REMINDER-TYPE).
  String get icsValue => switch (this) {
        ReminderType.push => 'PUSH',
        ReminderType.fullScreen => 'FULLSCREEN',
        ReminderType.alarm => 'ALARM',
      };

  static ReminderType? fromIcs(String? value) => switch (value?.trim().toUpperCase()) {
        'PUSH' => ReminderType.push,
        'FULLSCREEN' => ReminderType.fullScreen,
        'ALARM' => ReminderType.alarm,
        _ => null,
      };

  static ReminderType fromName(String? name) =>
      ReminderType.values.firstWhere((t) => t.name == name, orElse: () => ReminderType.push);
}

/// Longest delay accepted (4 weeks, same limit as Google Calendar).
const maxReminderMinutes = 4 * 7 * 24 * 60;

class Reminder implements Comparable<Reminder> {
  const Reminder(this.minutesBefore, this.type);

  /// Minutes before the start of the event. Negative values fire after the
  /// start, which is how "the same day at 9:00" is expressed for all-day
  /// events (start = midnight).
  final int minutesBefore;
  final ReminderType type;

  DateTime fireTime(DateTime eventStart) =>
      eventStart.subtract(Duration(minutes: minutesBefore));

  Map<String, Object> toJson() => {'m': minutesBefore, 't': type.name};

  static Reminder fromJson(Map<String, dynamic> json) =>
      Reminder((json['m'] as num).toInt(), ReminderType.fromName(json['t'] as String?));

  static String encodeList(List<Reminder> reminders) =>
      jsonEncode([for (final r in reminders) r.toJson()]);

  static List<Reminder> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final item in jsonDecode(json) as List) Reminder.fromJson(item as Map<String, dynamic>)
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Sorted (earliest alert first) without duplicates.
  static List<Reminder> normalize(Iterable<Reminder> reminders) {
    final set = <Reminder>{...reminders};
    return set.toList()..sort();
  }

  @override
  int compareTo(Reminder other) {
    final c = other.minutesBefore.compareTo(minutesBefore);
    return c != 0 ? c : type.index.compareTo(other.type.index);
  }

  @override
  bool operator ==(Object other) =>
      other is Reminder && other.minutesBefore == minutesBefore && other.type == type;

  @override
  int get hashCode => Object.hash(minutesBefore, type);

  @override
  String toString() => 'Reminder($minutesBefore min, ${type.name})';
}

/// A reusable reminder offered in the editor.
class ReminderPreset {
  const ReminderPreset({
    required this.id,
    required this.reminder,
    this.name,
    this.allDay = false,
  });

  final String id;

  /// Optional label ("Réveil du matin"); a description is generated otherwise.
  final String? name;
  final Reminder reminder;

  /// Preset meant for all-day events (delay counted from midnight).
  final bool allDay;

  ReminderPreset copyWith({String? name, bool clearName = false, Reminder? reminder, bool? allDay}) =>
      ReminderPreset(
        id: id,
        name: clearName ? null : (name ?? this.name),
        reminder: reminder ?? this.reminder,
        allDay: allDay ?? this.allDay,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        ...reminder.toJson(),
        'allDay': allDay,
      };

  static ReminderPreset fromJson(Map<String, dynamic> json) => ReminderPreset(
        id: json['id'] as String,
        name: json['name'] as String?,
        reminder: Reminder.fromJson(json),
        allDay: json['allDay'] as bool? ?? false,
      );

  static String encodeList(List<ReminderPreset> presets) =>
      jsonEncode([for (final p in presets) p.toJson()]);

  static List<ReminderPreset>? decodeList(String? json) {
    if (json == null) return null;
    try {
      return [
        for (final item in jsonDecode(json) as List)
          ReminderPreset.fromJson(item as Map<String, dynamic>)
      ];
    } catch (_) {
      return null;
    }
  }
}

/// Delays offered by default in the editor (same as Google Calendar).
const builtInTimedDelays = [0, 5, 10, 15, 30, 60, 24 * 60];

/// All-day events: the same day at 9:00, the day before at 17:00 / 9:00,
/// two days and one week before at 9:00.
const builtInAllDayDelays = [-9 * 60, 7 * 60, 15 * 60, (24 + 15) * 60, (6 * 24 + 15) * 60];

/// For all-day events: (days before, time of day) of a delay.
({int daysBefore, int hour, int minute}) allDayDelayParts(int minutesBefore) {
  // fire = midnight - minutesBefore  →  day offset and time of day.
  final fromMidnight = -minutesBefore; // minutes after the event's midnight
  var days = (fromMidnight / (24 * 60)).floor();
  final inDay = fromMidnight - days * 24 * 60;
  return (daysBefore: -days, hour: inDay ~/ 60, minute: inDay % 60);
}

int allDayDelay({required int daysBefore, required int hour, required int minute}) =>
    daysBefore * 24 * 60 - (hour * 60 + minute);
