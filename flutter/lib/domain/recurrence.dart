import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/date_utils.dart';
import '../core/time_zone.dart';
import 'models.dart';

/// Expands events into concrete occurrences.
///
/// Recurrences are computed in the event's own time zone (wall-clock time) so
/// that a weekly 9:00 meeting stays at 9:00 across DST changes.
class RecurrenceExpander {
  const RecurrenceExpander({this.maxIterations = 10000});

  final int maxIterations;

  /// Returns the `(start, end)` of every occurrence of [event] that overlaps
  /// [range].
  List<(DateTime, DateTime)> occurrences(CalendarEvent event, DateRange range) {
    if (!event.isRecurring) {
      return range.overlaps(event.start, event.end)
          ? [(event.start, event.end)]
          : const [];
    }
    try {
      return _expand(event, range);
    } catch (_) {
      // Unsupported rule: fall back to the first occurrence only.
      return range.overlaps(event.start, event.end)
          ? [(event.start, event.end)]
          : const [];
    }
  }

  List<(DateTime, DateTime)> _expand(CalendarEvent event, DateRange range) {
    final parsed = parseRrule(event.rrule!);
    final rule = RecurrenceRule.fromString('RRULE:${parsed.ruleWithoutUntil}');
    final loc = _location(event.timeZone);

    final DateTime baseWall;
    if (event.allDay) {
      baseWall = DateTime.utc(event.start.year, event.start.month, event.start.day);
    } else {
      baseWall = _toWall(event.start, loc);
    }

    DateTime? untilWall;
    final until = parsed.until;
    if (until != null) {
      if (until.isDateOnly) {
        // Inclusive date: allow every occurrence starting that day.
        untilWall = DateTime.utc(until.value.year, until.value.month,
            until.value.day, 23, 59, 59);
      } else if (until.isUtc) {
        untilWall = event.allDay
            ? DateTime.utc(until.value.year, until.value.month, until.value.day,
                23, 59, 59)
            : _toWall(until.value.toLocal(), loc);
      } else {
        untilWall = until.value;
      }
    }

    final duration = event.allDay
        ? Duration(days: daysBetween(event.start, event.end))
        : event.end.difference(event.start);

    // Wall-clock search window, with a margin for DST / time zone offsets.
    final afterWall = (event.allDay
            ? DateTime.utc(range.start.year, range.start.month, range.start.day)
            : _toWall(range.start, loc))
        .subtract(duration)
        .subtract(const Duration(days: 2));
    final beforeWall = (event.allDay
            ? DateTime.utc(range.end.year, range.end.month, range.end.day)
            : _toWall(range.end, loc))
        .add(const Duration(days: 2));

    if (baseWall.isAfter(beforeWall)) return const [];

    final excluded = {for (final d in event.exdates) _key(d, event.allDay)};

    final result = <(DateTime, DateTime)>[];
    var iterations = 0;
    var sawBase = false;

    void consider(DateTime wall) {
      final start = event.allDay
          ? DateTime(wall.year, wall.month, wall.day)
          : _fromWall(wall, loc);
      final end = event.allDay
          ? addDays(start, duration.inDays)
          : start.add(duration);
      if (excluded.contains(_key(start, event.allDay))) return;
      if (range.overlaps(start, end)) result.add((start, end));
    }

    for (final wall in rule.getInstances(start: baseWall)) {
      if (++iterations > maxIterations) break;
      if (untilWall != null && wall.isAfter(untilWall)) break;
      if (wall.isAfter(beforeWall)) break;
      if (wall == baseWall) sawBase = true;
      if (wall.isBefore(afterWall)) continue;
      consider(wall);
    }
    // RFC 5545: DTSTART is always the first occurrence, even if it does not
    // match the rule.
    if (!sawBase && !baseWall.isBefore(afterWall)) {
      consider(baseWall);
      result.sort((a, b) => a.$1.compareTo(b.$1));
    }
    return result;
  }

  static String _key(DateTime d, bool allDay) => allDay
      ? '${d.year}-${d.month}-${d.day}'
      : d.toUtc().millisecondsSinceEpoch.toString();

  static tz.Location _location(String? name) {
    if (name != null) {
      try {
        return tz.getLocation(name);
      } catch (_) {}
    }
    return deviceLocation;
  }

  /// Wall-clock time of [instant] in [loc], encoded as a UTC DateTime (the
  /// representation expected by the rrule package).
  static DateTime _toWall(DateTime instant, tz.Location loc) {
    final t = tz.TZDateTime.from(instant, loc);
    return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }

  static DateTime _fromWall(DateTime wall, tz.Location loc) =>
      DateTime.fromMillisecondsSinceEpoch(tz.TZDateTime(
        loc,
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
        wall.second,
      ).millisecondsSinceEpoch);
}

/// A parsed `UNTIL` value.
class RruleUntil {
  const RruleUntil(this.value, {required this.isDateOnly, required this.isUtc});

  /// Date/time fields as written in the rule (encoded as a UTC DateTime).
  final DateTime value;
  final bool isDateOnly;
  final bool isUtc;
}

class ParsedRrule {
  const ParsedRrule(this.parts, this.ruleWithoutUntil, this.until);

  final Map<String, String> parts;
  final String ruleWithoutUntil;
  final RruleUntil? until;

  String? get freq => parts['FREQ'];
  int get interval => int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
  int? get count => int.tryParse(parts['COUNT'] ?? '');
  List<String> get byDay =>
      parts['BYDAY']?.split(',').where((s) => s.isNotEmpty).toList() ?? const [];
}

ParsedRrule parseRrule(String rule) {
  var r = rule.trim();
  if (r.toUpperCase().startsWith('RRULE:')) r = r.substring(6);
  final parts = <String, String>{};
  final kept = <String>[];
  RruleUntil? until;
  for (final part in r.split(';')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq < 0) continue;
    final key = part.substring(0, eq).toUpperCase();
    final value = part.substring(eq + 1);
    parts[key] = value;
    if (key == 'UNTIL') {
      until = _parseUntil(value);
    } else {
      kept.add('$key=$value');
    }
  }
  return ParsedRrule(parts, kept.join(';'), until);
}

RruleUntil? _parseUntil(String v) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$')
      .firstMatch(v.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!),
      d = int.parse(m.group(3)!);
  if (m.group(4) == null) {
    return RruleUntil(DateTime.utc(y, mo, d), isDateOnly: true, isUtc: false);
  }
  return RruleUntil(
    DateTime.utc(y, mo, d, int.parse(m.group(4)!), int.parse(m.group(5)!),
        int.parse(m.group(6)!)),
    isDateOnly: false,
    isUtc: m.group(7) != null,
  );
}

/// Simple recurrence presets offered by the event editor (same as Google
/// Calendar's quick choices).
enum RecurrencePreset { none, daily, weekly, monthly, yearly, weekdays, custom }

const _weekdayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

String weekdayCode(DateTime d) => _weekdayCodes[d.weekday - 1];

/// Builds the rule string for a preset, relative to the event start.
String? rruleForPreset(RecurrencePreset preset, DateTime start) {
  switch (preset) {
    case RecurrencePreset.none:
    case RecurrencePreset.custom:
      return null;
    case RecurrencePreset.daily:
      return 'FREQ=DAILY';
    case RecurrencePreset.weekly:
      return 'FREQ=WEEKLY;BYDAY=${weekdayCode(start)}';
    case RecurrencePreset.monthly:
      return 'FREQ=MONTHLY;BYMONTHDAY=${start.day}';
    case RecurrencePreset.yearly:
      return 'FREQ=YEARLY';
    case RecurrencePreset.weekdays:
      return 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR';
  }
}

/// Detects which preset (if any) a rule corresponds to.
RecurrencePreset presetForRrule(String? rule) {
  if (rule == null || rule.isEmpty) return RecurrencePreset.none;
  final p = parseRrule(rule);
  final simple = p.interval == 1 && p.count == null && p.until == null;
  final otherKeys = p.parts.keys
      .where((k) => !const {'FREQ', 'BYDAY', 'BYMONTHDAY', 'WKST', 'INTERVAL'}
          .contains(k))
      .isNotEmpty;
  if (!simple || otherKeys) return RecurrencePreset.custom;
  switch (p.freq) {
    case 'DAILY':
      return p.byDay.isEmpty ? RecurrencePreset.daily : RecurrencePreset.custom;
    case 'WEEKLY':
      if (p.byDay.length == 5 &&
          p.byDay.toSet().containsAll(const ['MO', 'TU', 'WE', 'TH', 'FR'])) {
        return RecurrencePreset.weekdays;
      }
      return p.byDay.length <= 1 ? RecurrencePreset.weekly : RecurrencePreset.custom;
    case 'MONTHLY':
      return p.byDay.isEmpty ? RecurrencePreset.monthly : RecurrencePreset.custom;
    case 'YEARLY':
      return RecurrencePreset.yearly;
  }
  return RecurrencePreset.custom;
}

/// Returns [rule] with an UNTIL set so that the series stops before
/// [occurrenceStart] ("this and following" edits / deletions).
String rruleEndingBefore(String rule, DateTime occurrenceStart, bool allDay) {
  final p = parseRrule(rule);
  final parts = Map.of(p.parts)
    ..remove('COUNT')
    ..remove('UNTIL');
  final until = allDay
      ? addDays(dateOnly(occurrenceStart), -1)
      : occurrenceStart.toUtc().subtract(const Duration(seconds: 1));
  String two(int v) => v.toString().padLeft(2, '0');
  parts['UNTIL'] = allDay
      ? '${until.year}${two(until.month)}${two(until.day)}'
      : '${until.year}${two(until.month)}${two(until.day)}T'
          '${two(until.hour)}${two(until.minute)}${two(until.second)}Z';
  return parts.entries.map((e) => '${e.key}=${e.value}').join(';');
}
