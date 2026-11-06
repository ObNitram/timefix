import 'package:timezone/timezone.dart' as tz;

/// A property line of an iCalendar file: `NAME;PARAM=VALUE:value`.
class IcsProperty {
  IcsProperty(this.name, this.params, this.value);

  final String name;
  final Map<String, String> params;
  final String value;

  String? param(String key) => params[key];
}

/// A VEVENT extracted from an .ics file.
class IcsEvent {
  IcsEvent({
    required this.uid,
    required this.summary,
    required this.start,
    required this.end,
    required this.allDay,
    this.description,
    this.location,
    this.timeZone,
    this.rrule,
    this.exdates = const [],
    this.recurrenceId,
    this.cancelled = false,
    this.lastModified,
    this.color,
  });

  final String uid;
  final String summary;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? description;
  final String? location;
  final String? timeZone;
  final String? rrule;
  final List<DateTime> exdates;

  /// Set when this VEVENT overrides one occurrence of a recurring event.
  final DateTime? recurrenceId;
  final bool cancelled;
  final DateTime? lastModified;

  /// Optional `COLOR` property (CSS color name or hex).
  final String? color;
}

class IcsCalendar {
  IcsCalendar({this.name, this.color, this.timeZone, required this.events});

  final String? name;
  final String? color;
  final String? timeZone;
  final List<IcsEvent> events;
}

class IcsParseException implements Exception {
  IcsParseException(this.message);
  final String message;
  @override
  String toString() => 'IcsParseException: $message';
}

/// Lenient RFC 5545 parser, covering what calendar providers (Google, Outlook,
/// iCloud, Proton, Nextcloud...) publish in their .ics feeds.
class IcsParser {
  IcsParser({this.defaultLocation});

  /// Zone used for floating times when the feed has no X-WR-TIMEZONE.
  final tz.Location? defaultLocation;

  IcsCalendar parse(String content) {
    final lines = unfold(content);
    if (!lines.any((l) => l.toUpperCase().startsWith('BEGIN:VCALENDAR'))) {
      throw IcsParseException('Not an iCalendar file');
    }

    String? calName;
    String? calColor;
    String? calTz;
    final events = <IcsEvent>[];
    final stack = <String>[];
    List<IcsProperty>? current;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final prop = parseLine(line);
      if (prop == null) continue;
      if (prop.name == 'BEGIN') {
        stack.add(prop.value.toUpperCase());
        if (prop.value.toUpperCase() == 'VEVENT' && stack.length == 2) {
          current = [];
        }
        continue;
      }
      if (prop.name == 'END') {
        final ended = stack.isNotEmpty ? stack.removeLast() : '';
        if (ended == 'VEVENT' && current != null) {
          final calLocation = _location(calTz) ?? defaultLocation;
          final e = _buildEvent(current, calLocation, calTz);
          if (e != null) events.add(e);
          current = null;
        }
        continue;
      }
      if (stack.length == 1 && stack.first == 'VCALENDAR') {
        switch (prop.name) {
          case 'X-WR-CALNAME':
          case 'NAME':
            calName ??= unescapeText(prop.value);
          case 'X-APPLE-CALENDAR-COLOR':
          case 'COLOR':
            calColor ??= prop.value;
          case 'X-WR-TIMEZONE':
            calTz ??= prop.value.trim();
        }
      } else if (current != null && stack.length == 2) {
        current.add(prop);
      }
    }

    return IcsCalendar(
        name: calName, color: calColor, timeZone: calTz, events: events);
  }

  IcsEvent? _buildEvent(
      List<IcsProperty> props, tz.Location? calLocation, String? calTz) {
    IcsProperty? get(String name) {
      for (final p in props) {
        if (p.name == name) return p;
      }
      return null;
    }

    final dtStartProp = get('DTSTART');
    if (dtStartProp == null) return null;
    final startParsed = parseDateValue(dtStartProp, calLocation);
    if (startParsed == null) return null;

    DateTime end;
    final dtEndProp = get('DTEND') ?? get('DUE');
    final durationProp = get('DURATION');
    final endParsed =
        dtEndProp == null ? null : parseDateValue(dtEndProp, calLocation);
    if (endParsed != null) {
      end = endParsed.value;
    } else if (durationProp != null) {
      final dur = parseDuration(durationProp.value) ?? Duration.zero;
      end = startParsed.isDate
          ? DateTime(startParsed.value.year, startParsed.value.month,
              startParsed.value.day + dur.inDays)
          : startParsed.value.add(dur);
    } else {
      end = startParsed.isDate
          ? DateTime(startParsed.value.year, startParsed.value.month,
              startParsed.value.day + 1)
          : startParsed.value;
    }
    if (end.isBefore(startParsed.value)) end = startParsed.value;
    if (startParsed.isDate && !end.isAfter(startParsed.value)) {
      end = DateTime(startParsed.value.year, startParsed.value.month,
          startParsed.value.day + 1);
    }

    final exdates = <DateTime>[];
    for (final p in props.where((p) => p.name == 'EXDATE')) {
      for (final v in p.value.split(',')) {
        final d = parseDateValue(IcsProperty('EXDATE', p.params, v), calLocation);
        if (d != null) exdates.add(d.value);
      }
    }

    final rruleProp = get('RRULE');
    final recurrenceIdProp = get('RECURRENCE-ID');
    final lastModProp = get('LAST-MODIFIED') ?? get('DTSTAMP');
    final status = get('STATUS')?.value.toUpperCase();

    return IcsEvent(
      uid: get('UID')?.value.trim() ??
          '${dtStartProp.value}-${get('SUMMARY')?.value.hashCode}',
      summary: unescapeText(get('SUMMARY')?.value ?? ''),
      description: _optText(get('DESCRIPTION')?.value),
      location: _optText(get('LOCATION')?.value),
      start: startParsed.value,
      end: end,
      allDay: startParsed.isDate,
      timeZone: startParsed.tzid ?? calTz ?? defaultLocation?.name,
      rrule: rruleProp?.value.trim(),
      exdates: exdates,
      recurrenceId: recurrenceIdProp == null
          ? null
          : parseDateValue(recurrenceIdProp, calLocation)?.value,
      cancelled: status == 'CANCELLED',
      lastModified:
          lastModProp == null ? null : parseDateValue(lastModProp, null)?.value,
      color: get('COLOR')?.value,
    );
  }

  String? _optText(String? v) {
    if (v == null) return null;
    final t = unescapeText(v).trim();
    return t.isEmpty ? null : t;
  }

  /// Parses a DATE or DATE-TIME value. Timed values are returned as local
  /// DateTimes representing the absolute instant; dates as local midnights.
  ParsedIcsDate? parseDateValue(IcsProperty prop, tz.Location? fallback) {
    final raw = prop.value.trim();
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$')
        .firstMatch(raw);
    if (m == null) return null;
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!),
        d = int.parse(m.group(3)!);
    final isDate = m.group(4) == null || prop.param('VALUE')?.toUpperCase() == 'DATE';
    if (isDate) {
      return ParsedIcsDate(DateTime(y, mo, d), isDate: true);
    }
    final h = int.parse(m.group(4)!), mi = int.parse(m.group(5)!),
        s = int.tryParse(m.group(6) ?? '') ?? 0;
    if (m.group(7) != null) {
      return ParsedIcsDate(DateTime.utc(y, mo, d, h, mi, s).toLocal(),
          isDate: false);
    }
    final tzid = prop.param('TZID');
    final loc = _location(tzid) ?? fallback;
    if (loc == null) {
      // Floating time: interpret in the device time zone.
      return ParsedIcsDate(DateTime(y, mo, d, h, mi, s), isDate: false);
    }
    final instant = tz.TZDateTime(loc, y, mo, d, h, mi, s);
    return ParsedIcsDate(
        DateTime.fromMillisecondsSinceEpoch(instant.millisecondsSinceEpoch),
        isDate: false,
        tzid: loc.name);
  }

  static tz.Location? _location(String? tzid) {
    if (tzid == null || tzid.isEmpty) return null;
    var name = tzid.trim().replaceAll('"', '');
    final candidates = <String>[name];
    // e.g. "/mozilla.org/20050126_1/Europe/Paris"
    final segments = name.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2) {
      candidates.add(segments.sublist(segments.length - 2).join('/'));
    }
    final windows = windowsZones[name];
    if (windows != null) candidates.add(windows);
    for (final c in candidates) {
      try {
        return tz.getLocation(c);
      } catch (_) {}
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Low level helpers
  // ---------------------------------------------------------------------------

  /// Joins folded lines (lines starting with a space or tab continue the
  /// previous one).
  static List<String> unfold(String content) {
    final raw = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final out = <String>[];
    for (final line in raw) {
      if ((line.startsWith(' ') || line.startsWith('\t')) && out.isNotEmpty) {
        out[out.length - 1] = out.last + line.substring(1);
      } else {
        out.add(line);
      }
    }
    return out;
  }

  static IcsProperty? parseLine(String line) {
    var inQuotes = false;
    int? colon;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') inQuotes = !inQuotes;
      if (c == ':' && !inQuotes) {
        colon = i;
        break;
      }
    }
    if (colon == null) return null;
    final head = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final segments = _splitOutsideQuotes(head, ';');
    final name = segments.first.trim().toUpperCase();
    final params = <String, String>{};
    for (final seg in segments.skip(1)) {
      final eq = seg.indexOf('=');
      if (eq <= 0) continue;
      var v = seg.substring(eq + 1);
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1);
      }
      params[seg.substring(0, eq).trim().toUpperCase()] = v;
    }
    return IcsProperty(name, params, value);
  }

  static List<String> _splitOutsideQuotes(String s, String sep) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') inQuotes = !inQuotes;
      if (c == sep && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }

  static String unescapeText(String v) {
    final buf = StringBuffer();
    for (var i = 0; i < v.length; i++) {
      final c = v[i];
      if (c == '\\' && i + 1 < v.length) {
        final n = v[i + 1];
        i++;
        switch (n) {
          case 'n':
          case 'N':
            buf.write('\n');
          default:
            buf.write(n);
        }
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  /// Parses an ISO 8601 / RFC 5545 duration such as `P1DT2H30M` or `-PT15M`.
  static Duration? parseDuration(String v) {
    final m = RegExp(r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$')
        .firstMatch(v.trim());
    if (m == null) return null;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    final d = Duration(
      days: g(2) * 7 + g(3),
      hours: g(4),
      minutes: g(5),
      seconds: g(6),
    );
    return m.group(1) == '-' ? -d : d;
  }
}

class ParsedIcsDate {
  ParsedIcsDate(this.value, {required this.isDate, this.tzid});
  final DateTime value;
  final bool isDate;
  final String? tzid;
}

/// Most common Windows time zone names used by Outlook / Exchange feeds.
const Map<String, String> windowsZones = {
  'Romance Standard Time': 'Europe/Paris',
  'W. Europe Standard Time': 'Europe/Berlin',
  'Central Europe Standard Time': 'Europe/Budapest',
  'Central European Standard Time': 'Europe/Warsaw',
  'GMT Standard Time': 'Europe/London',
  'Greenwich Standard Time': 'Atlantic/Reykjavik',
  'E. Europe Standard Time': 'Europe/Chisinau',
  'FLE Standard Time': 'Europe/Kiev',
  'GTB Standard Time': 'Europe/Bucharest',
  'Russian Standard Time': 'Europe/Moscow',
  'Eastern Standard Time': 'America/New_York',
  'Central Standard Time': 'America/Chicago',
  'Mountain Standard Time': 'America/Denver',
  'Pacific Standard Time': 'America/Los_Angeles',
  'Atlantic Standard Time': 'America/Halifax',
  'Canada Central Standard Time': 'America/Regina',
  'E. South America Standard Time': 'America/Sao_Paulo',
  'Morocco Standard Time': 'Africa/Casablanca',
  'W. Central Africa Standard Time': 'Africa/Lagos',
  'South Africa Standard Time': 'Africa/Johannesburg',
  'Arabian Standard Time': 'Asia/Dubai',
  'India Standard Time': 'Asia/Kolkata',
  'China Standard Time': 'Asia/Shanghai',
  'Tokyo Standard Time': 'Asia/Tokyo',
  'Singapore Standard Time': 'Asia/Singapore',
  'AUS Eastern Standard Time': 'Australia/Sydney',
  'New Zealand Standard Time': 'Pacific/Auckland',
  'UTC': 'UTC',
  'Coordinated Universal Time': 'UTC',
};
