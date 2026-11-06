import 'dart:convert';
import 'dart:ui' show Color;

import 'package:http/http.dart' as http;

import '../../core/colors.dart';
import '../../core/time_zone.dart';
import '../../domain/models.dart';
import 'ics_parser.dart';

class IcalFetchException implements Exception {
  IcalFetchException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads iCalendar subscriptions and converts them into [CalendarEvent]s.
class IcalService {
  IcalService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Accepts `webcal://`, `webcals://`, `http(s)://` and bare host URLs.
  static Uri normalizeUrl(String input) {
    var url = input.trim();
    if (url.startsWith('webcals://')) {
      url = 'https://${url.substring(10)}';
    } else if (url.startsWith('webcal://')) {
      url = 'https://${url.substring(9)}';
    } else if (!url.contains('://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw IcalFetchException('Invalid URL');
    }
    return uri;
  }

  Future<IcsCalendar> fetch(String url) async {
    final uri = normalizeUrl(url);
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'Accept': 'text/calendar, */*'})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw IcalFetchException('Network error: $e');
    }
    if (response.statusCode != 200) {
      throw IcalFetchException('HTTP ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    try {
      return IcsParser(defaultLocation: deviceTimeZoneName == null ? null : deviceLocation).parse(body);
    } on IcsParseException catch (e) {
      throw IcalFetchException(e.message);
    }
  }

  /// Converts parsed VEVENTs into events of [calendarId]. Occurrence overrides
  /// (`RECURRENCE-ID`) become standalone events and are excluded from their
  /// series.
  static List<CalendarEvent> toEvents(IcsCalendar cal, String calendarId) {
    final masters = <String, IcsEvent>{};
    final overrides = <IcsEvent>[];
    for (final e in cal.events) {
      if (e.recurrenceId != null) {
        overrides.add(e);
      } else {
        masters[e.uid] = e;
      }
    }
    final extraExdates = <String, List<DateTime>>{};
    for (final o in overrides) {
      extraExdates.putIfAbsent(o.uid, () => []).add(o.recurrenceId!);
    }

    CalendarEvent convert(IcsEvent e, String id) => CalendarEvent(
          id: id,
          calendarId: calendarId,
          remoteId: e.uid,
          title: e.summary,
          description: e.description,
          location: e.location,
          start: e.start,
          end: e.end,
          allDay: e.allDay,
          timeZone: e.timeZone,
          rrule: e.recurrenceId == null ? e.rrule : null,
          exdates: [...e.exdates, ...?extraExdates[e.uid]],
          color: e.color == null ? null : _cssColor(e.color!),
          updatedAt: e.lastModified,
        );

    final result = <CalendarEvent>[];
    for (final m in masters.values) {
      if (m.cancelled) continue;
      result.add(convert(m, '$calendarId|${m.uid}'));
    }
    for (final o in overrides) {
      if (o.cancelled) continue;
      result.add(convert(
          o, '$calendarId|${o.uid}|${o.recurrenceId!.millisecondsSinceEpoch}'));
    }
    return result;
  }

  static final _cssColors = <String, int>{
    'red': 0xFFD50000,
    'orange': 0xFFF4511E,
    'yellow': 0xFFF6BF26,
    'green': 0xFF0B8043,
    'blue': 0xFF039BE5,
    'purple': 0xFF8E24AA,
    'gray': 0xFF616161,
    'grey': 0xFF616161,
    'pink': 0xFFE67C73,
  };

  static Color? _cssColor(String v) {
    final named = _cssColors[v.toLowerCase().trim()];
    if (named != null) return Color(named);
    if (v.trim().startsWith('#')) return parseHexColor(v);
    return null;
  }
}
