import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../../domain/models.dart';
import '../../domain/reminders.dart';

/// Serializes events into an iCalendar resource (RFC 5545).
class IcsWriter {
  static const prodId = '-//TimeFix//App//EN';

  /// Builds one calendar object resource from a series and its overrides
  /// (all with the same UID). The master comes first; EXDATEs that only exist
  /// because an override replaces the occurrence are not written.
  static String resource(List<CalendarEvent> events, {DateTime? now}) {
    if (events.isEmpty) throw ArgumentError('No event');
    final sorted = [...events]
      ..sort((a, b) => (a.recurrenceId == null ? 0 : 1).compareTo(b.recurrenceId == null ? 0 : 1));
    final overrideIds = {
      for (final e in sorted)
        if (e.recurrenceId != null) _key(e.recurrenceId!, e.allDay)
    };
    final master = sorted.first.recurrenceId == null ? sorted.first : null;
    final zone = _zone(master?.timeZone ?? sorted.first.timeZone);
    final stamp = _utc(now ?? DateTime.now());

    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:$prodId',
      'CALSCALE:GREGORIAN',
    ];
    for (final e in sorted) {
      final uid = e.remoteId ?? e.id;
      lines.add('BEGIN:VEVENT');
      lines.add('UID:${_escape(uid)}');
      lines.add('DTSTAMP:$stamp');
      if (e.recurrenceId != null) {
        lines.add(_dateProp('RECURRENCE-ID', e.recurrenceId!, e.allDay, zone));
      }
      lines.add(_dateProp('DTSTART', e.start, e.allDay, zone));
      lines.add(_dateProp('DTEND', e.end, e.allDay, zone));
      if (e.title.isNotEmpty) lines.add('SUMMARY:${_escape(e.title)}');
      if (e.location?.isNotEmpty ?? false) lines.add('LOCATION:${_escape(e.location!)}');
      if (e.description?.isNotEmpty ?? false) {
        lines.add('DESCRIPTION:${_escape(e.description!)}');
      }
      if (e.recurrenceId == null && e.isRecurring) {
        lines.add('RRULE:${e.rrule}');
        for (final x in e.exdates) {
          if (overrideIds.contains(_key(x, e.allDay))) continue;
          lines.add(_dateProp('EXDATE', x, e.allDay, zone));
        }
      }
      if (e.color != null) {
        final rgb = e.color!.toARGB32() & 0xFFFFFF;
        lines.add('X-TIMEFIX-COLOR:#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}');
      }
      if (e.updatedAt != null) lines.add('LAST-MODIFIED:${_utc(e.updatedAt!)}');
      for (final r in e.reminders) {
        lines.addAll(_alarm(r, e.title));
      }
      lines.add('END:VEVENT');
    }
    lines.add('END:VCALENDAR');
    return '${lines.map(fold).join('\r\n')}\r\n';
  }

  /// A VALARM understood by any client (DISPLAY, or AUDIO for alarms), with
  /// the TimeFix type in an extension property.
  static List<String> _alarm(Reminder r, String title) => [
        'BEGIN:VALARM',
        'ACTION:${r.type == ReminderType.alarm ? 'AUDIO' : 'DISPLAY'}',
        'TRIGGER:${triggerValue(r.minutesBefore)}',
        'DESCRIPTION:${_escape(title.isEmpty ? 'Reminder' : title)}',
        'X-TIMEFIX-REMINDER-TYPE:${r.type.icsValue}',
        'END:VALARM',
      ];

  /// RFC 5545 duration relative to the start: "-PT10M", "-P1D", "PT9H".
  static String triggerValue(int minutesBefore) {
    if (minutesBefore == 0) return 'PT0S';
    final sign = minutesBefore > 0 ? '-' : '';
    final m = minutesBefore.abs();
    if (m % (24 * 60) == 0) return '${sign}P${m ~/ (24 * 60)}D';
    if (m % 60 == 0) return '${sign}PT${m ~/ 60}H';
    return '${sign}PT${m}M';
  }

  static String _key(DateTime d, bool allDay) => allDay
      ? '${d.year}-${d.month}-${d.day}'
      : d.toUtc().millisecondsSinceEpoch.toString();

  static tz.Location? _zone(String? name) {
    if (name == null || name == 'UTC') return null;
    try {
      return tz.getLocation(name);
    } catch (_) {
      return null;
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  static String _time(DateTime d) => '${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

  static String _utc(DateTime d) {
    final u = d.toUtc();
    return '${_date(u)}T${_time(u)}Z';
  }

  /// DATE for all-day events, local time with TZID when the zone is known
  /// (keeps recurrences on the same wall-clock time across DST), UTC otherwise.
  static String _dateProp(String name, DateTime d, bool allDay, tz.Location? zone) {
    if (allDay) return '$name;VALUE=DATE:${_date(d)}';
    if (zone != null) {
      final local = tz.TZDateTime.from(d, zone);
      return '$name;TZID=${zone.name}:${_date(local)}T${_time(local)}';
    }
    return '$name:${_utc(d)}';
  }

  static String _escape(String v) => v
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n');

  /// Folds a content line at 75 octets without splitting UTF-8 sequences.
  static String fold(String line) {
    if (utf8.encode(line).length <= 75) return line;
    final out = StringBuffer();
    var count = 0;
    var limit = 75;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final size = utf8.encode(ch).length;
      if (count + size > limit) {
        out.write('\r\n ');
        count = 0;
        limit = 74; // the leading space counts
      }
      out.write(ch);
      count += size;
    }
    return out.toString();
  }
}
