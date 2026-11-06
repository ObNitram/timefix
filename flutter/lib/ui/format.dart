import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/colors.dart';
import '../core/date_utils.dart';
import '../domain/models.dart';
import '../domain/recurrence.dart';
import '../l10n/generated/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String get localeName => Localizations.localeOf(this).toLanguageTag();
}

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "14:30" or "2:30 PM" depending on locale and device settings.
String formatTime(BuildContext context, DateTime d) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(d),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context) ||
          !DateFormat.jm(context.localeName).pattern!.contains('a'),
    );

/// Label displayed next to the hour lines of the week grid ("14:00", "2 PM").
String formatHourLabel(BuildContext context, int hour) {
  final d = DateTime(2000, 1, 1, hour);
  final uses24 = MediaQuery.alwaysUse24HourFormatOf(context) ||
      !DateFormat.jm(context.localeName).pattern!.contains('a');
  return uses24 ? DateFormat.Hm(context.localeName).format(d) : DateFormat.j(context.localeName).format(d);
}

/// Title of the app bar: "Novembre" or "Novembre 2027" outside the current year.
String formatMonthTitle(BuildContext context, DateTime d) {
  final now = DateTime.now();
  final pattern = d.year == now.year ? DateFormat.MMMM : DateFormat.yMMMM;
  return capitalize(pattern(context.localeName).format(d));
}

/// "vendredi 6 novembre" (+ year when not the current year).
String formatLongDate(BuildContext context, DateTime d) {
  final now = DateTime.now();
  final f = d.year == now.year
      ? DateFormat.MMMMEEEEd(context.localeName)
      : DateFormat.yMMMMEEEEd(context.localeName);
  return capitalize(f.format(d));
}

String formatShortDate(BuildContext context, DateTime d) {
  final now = DateTime.now();
  final f = d.year == now.year
      ? DateFormat.MMMEd(context.localeName)
      : DateFormat.yMMMEd(context.localeName);
  return capitalize(f.format(d));
}

/// "2 – 8 nov." / "29 déc. – 4 janv."
String formatWeekRange(BuildContext context, DateTime start, DateTime endInclusive) {
  final loc = context.localeName;
  if (start.month == endInclusive.month) {
    return '${DateFormat.d(loc).format(start)} – ${DateFormat.MMMd(loc).format(endInclusive)}';
  }
  return '${DateFormat.MMMd(loc).format(start)} – ${DateFormat.MMMd(loc).format(endInclusive)}';
}

/// Time label of an occurrence as seen on [day] (schedule view, sheets).
String formatOccurrenceTime(BuildContext context, EventOccurrence o, {DateTime? day}) {
  final l10n = context.l10n;
  if (o.allDay) return l10n.allDay;
  final sameDay = isSameDay(o.start, o.end) ||
      o.end == addDays(dateOnly(o.start), 1);
  if (sameDay) {
    if (o.start == o.end) return formatTime(context, o.start);
    return '${formatTime(context, o.start)} – ${formatTime(context, o.end)}';
  }
  final loc = context.localeName;
  return '${DateFormat.MMMd(loc).format(o.start)}, ${formatTime(context, o.start)} – '
      '${DateFormat.MMMd(loc).format(o.end)}, ${formatTime(context, o.end)}';
}

/// Full date/time description used in the event details page.
String formatOccurrenceDetails(BuildContext context, EventOccurrence o) {
  if (o.allDay) {
    final lastDay = addDays(o.end, -1);
    if (!lastDay.isAfter(o.start)) return formatLongDate(context, o.start);
    return '${formatLongDate(context, o.start)} – ${formatLongDate(context, lastDay)}';
  }
  if (isSameDay(o.start, o.end)) {
    return '${formatLongDate(context, o.start)}\n'
        '${formatTime(context, o.start)} – ${formatTime(context, o.end)}';
  }
  return '${formatLongDate(context, o.start)}, ${formatTime(context, o.start)} –\n'
      '${formatLongDate(context, o.end)}, ${formatTime(context, o.end)}';
}

String weekdayName(BuildContext context, DateTime d) =>
    DateFormat.EEEE(context.localeName).format(d);

String recurrencePresetLabel(
    BuildContext context, RecurrencePreset preset, DateTime start) {
  final l10n = context.l10n;
  switch (preset) {
    case RecurrencePreset.none:
      return l10n.repeatNone;
    case RecurrencePreset.daily:
      return l10n.repeatDaily;
    case RecurrencePreset.weekly:
      return l10n.repeatWeekly(weekdayName(context, start));
    case RecurrencePreset.monthly:
      return l10n.repeatMonthly(start.day);
    case RecurrencePreset.yearly:
      return l10n.repeatYearly(DateFormat.MMMMd(context.localeName).format(start));
    case RecurrencePreset.weekdays:
      return l10n.repeatWeekdays;
    case RecurrencePreset.custom:
      return l10n.repeatCustom;
  }
}

const _dayCodes = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};

/// Human readable description of any RRULE.
String describeRrule(BuildContext context, String rule, DateTime start) {
  final preset = presetForRrule(rule);
  if (preset != RecurrencePreset.custom) {
    return recurrencePresetLabel(context, preset, start);
  }
  final l10n = context.l10n;
  final p = parseRrule(rule);
  String base;
  switch (p.freq) {
    case 'DAILY':
      base = l10n.repeatEveryNDays(p.interval);
    case 'WEEKLY':
      base = l10n.repeatEveryNWeeks(p.interval);
    case 'MONTHLY':
      base = l10n.repeatEveryNMonths(p.interval);
    case 'YEARLY':
      base = l10n.repeatEveryNYears(p.interval);
    default:
      return l10n.repeatCustom;
  }
  final days = <String>[];
  for (final code in p.byDay) {
    final wd = _dayCodes[code.length > 2 ? code.substring(code.length - 2) : code];
    if (wd == null) continue;
    // 2023-01-02 is a Monday.
    days.add(DateFormat.EEEE(context.localeName).format(DateTime(2023, 1, 1 + wd)));
  }
  if (days.isNotEmpty && p.freq == 'WEEKLY') {
    base = l10n.repeatOnDays(base, days.join(', '));
  }
  if (p.until != null) {
    final u = p.until!.value;
    base = l10n.repeatUntil(base,
        DateFormat.yMMMd(context.localeName).format(DateTime(u.year, u.month, u.day)));
  } else if (p.count != null) {
    base = l10n.repeatCount(base, p.count!);
  }
  return base;
}

String colorName(BuildContext context, PaletteColor c) {
  final l = context.l10n;
  return switch (c.key) {
    'tomato' => l.colorTomato,
    'flamingo' => l.colorFlamingo,
    'tangerine' => l.colorTangerine,
    'banana' => l.colorBanana,
    'sage' => l.colorSage,
    'basil' => l.colorBasil,
    'peacock' => l.colorPeacock,
    'blueberry' => l.colorBlueberry,
    'lavender' => l.colorLavender,
    'grape' => l.colorGrape,
    _ => l.colorGraphite,
  };
}

String eventTitle(BuildContext context, CalendarEvent e) =>
    e.title.trim().isEmpty ? context.l10n.noTitle : e.title;
