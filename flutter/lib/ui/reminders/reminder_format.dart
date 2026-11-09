import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/reminders.dart';
import '../../l10n/generated/app_localizations.dart';
import '../format.dart';

IconData reminderTypeIcon(ReminderType type) => switch (type) {
      ReminderType.push => Icons.notifications_outlined,
      ReminderType.fullScreen => Icons.fullscreen,
      ReminderType.alarm => Icons.alarm,
    };

String reminderTypeLabel(AppLocalizations l10n, ReminderType type) => switch (type) {
      ReminderType.push => l10n.reminderTypePush,
      ReminderType.fullScreen => l10n.reminderTypeFullScreen,
      ReminderType.alarm => l10n.reminderTypeAlarm,
    };

/// "10 minutes avant", "1 jour avant", "La veille à 09:00"…
/// Works without a BuildContext (notifications are built in the background).
String describeReminderDelay(AppLocalizations l10n, String localeName, int minutesBefore,
    {required bool allDay}) {
  if (allDay) {
    final parts = allDayDelayParts(minutesBefore);
    final time = DateFormat.Hm(localeName).format(DateTime(2000, 1, 1, parts.hour, parts.minute));
    return switch (parts.daysBefore) {
      0 => l10n.reminderSameDayAt(time),
      1 => l10n.reminderDayBeforeAt(time),
      _ => l10n.reminderDaysBeforeAt(parts.daysBefore, time),
    };
  }
  final m = minutesBefore;
  if (m == 0) return l10n.reminderAtStart;
  if (m < 0) return l10n.reminderMinutesAfter(-m);
  if (m % (7 * 24 * 60) == 0) return l10n.reminderWeeksBefore(m ~/ (7 * 24 * 60));
  if (m % (24 * 60) == 0) return l10n.reminderDaysBefore(m ~/ (24 * 60));
  if (m % 60 == 0) return l10n.reminderHoursBefore(m ~/ 60);
  if (m < 60) return l10n.reminderMinutesBefore(m);
  return l10n.reminderHoursMinutesBefore(m ~/ 60, m % 60);
}

extension ReminderText on BuildContext {
  String reminderDelay(int minutesBefore, {required bool allDay}) =>
      describeReminderDelay(l10n, localeName, minutesBefore, allDay: allDay);

  String reminderSummary(Reminder r, {required bool allDay}) =>
      '${reminderDelay(r.minutesBefore, allDay: allDay)} · ${reminderTypeLabel(l10n, r.type)}';

  String presetLabel(ReminderPreset p) =>
      (p.name?.trim().isNotEmpty ?? false) ? p.name!.trim() : reminderSummary(p.reminder, allDay: p.allDay);
}
