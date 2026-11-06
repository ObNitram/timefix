import 'dart:convert';
import 'dart:ui' show Color;

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../core/colors.dart';

const _dav = 'DAV:';
const _caldav = 'urn:ietf:params:xml:ns:caldav';
const _cs = 'http://calendarserver.org/ns/';
const _apple = 'http://apple.com/ns/ical/';

class CalDavException implements Exception {
  CalDavException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class CalDavAuthException extends CalDavException {
  CalDavAuthException() : super('Authentication failed (401)', statusCode: 401);
}

/// The resource was modified on the server since it was last downloaded.
class CalDavConflictException extends CalDavException {
  CalDavConflictException() : super('Modified on the server (412)', statusCode: 412);
}

class CalDavCalendar {
  CalDavCalendar({
    required this.url,
    required this.displayName,
    this.color,
    this.ctag,
    this.readOnly = false,
  });

  final Uri url;
  final String displayName;
  final Color? color;
  final String? ctag;
  final bool readOnly;
}

class CalDavObject {
  CalDavObject({required this.url, required this.etag, required this.data});
  final Uri url;
  final String? etag;
  final String data;
}

class CalDavAccount {
  CalDavAccount({required this.principal, required this.home, required this.calendars});
  final Uri principal;
  final Uri home;
  final List<CalDavCalendar> calendars;
}

/// Minimal CalDAV client (RFC 4791): discovery, calendar listing, event
/// download (calendar-query) and writes with ETag preconditions.
class CalDavClient {
  CalDavClient({required this.username, required this.password, http.Client? client})
      : _client = client ?? http.Client();

  final String username;
  final String password;
  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  String get _auth => 'Basic ${base64.encode(utf8.encode('$username:$password'))}';

  /// Accepts "cal.example.com", "https://cal.example.com" or a full DAV URL.
  static Uri normalizeServerUrl(String input) {
    var url = input.trim();
    if (!url.contains('://')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw CalDavException('Invalid URL');
    }
    return uri.path.isEmpty ? uri.replace(path: '/') : uri;
  }

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  Future<_Response> _send(
    String method,
    Uri url, {
    String? body,
    String contentType = 'application/xml; charset=utf-8',
    Map<String, String> headers = const {},
  }) async {
    var target = url;
    for (var redirects = 0; redirects < 5; redirects++) {
      final request = http.Request(method, target)
        ..followRedirects = false
        ..headers['Authorization'] = _auth
        ..headers.addAll(headers);
      if (body != null) {
        request.headers['Content-Type'] = contentType;
        request.bodyBytes = utf8.encode(body);
      }
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      final location = response.headers['location'];
      if (const {301, 302, 303, 307, 308}.contains(response.statusCode) && location != null) {
        target = target.resolve(location);
        continue;
      }
      if (response.statusCode == 401) throw CalDavAuthException();
      return _Response(target, response);
    }
    throw CalDavException('Too many redirects');
  }

  Future<List<_DavResponse>> _propfind(Uri url, String props, {int depth = 0}) async {
    final r = await _send('PROPFIND', url, headers: {'Depth': '$depth'}, body: '''
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:i="http://apple.com/ns/ical/">
  <d:prop>$props</d:prop>
</d:propfind>''');
    if (r.response.statusCode != 207) {
      throw CalDavException('PROPFIND ${r.response.statusCode} on $url', statusCode: r.response.statusCode);
    }
    return _parseMultistatus(r.url, r.response);
  }

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// Finds the principal and calendar home from a server URL, then lists the
  /// calendars.
  Future<CalDavAccount> discover(String serverUrl) async {
    final base = normalizeServerUrl(serverUrl);
    final candidates = <Uri>[
      base,
      base.replace(path: '/.well-known/caldav'),
      base.replace(path: '/dav/'),
    ];
    Uri? principal;
    CalDavException? lastError;
    for (final candidate in candidates) {
      try {
        final responses = await _propfind(candidate, '<d:current-user-principal/>');
        final href = responses.map((r) => r.href(_dav, 'current-user-principal')).nonNulls.firstOrNull;
        if (href != null) {
          principal = responses.first.base.resolve(href);
          break;
        }
      } on CalDavAuthException {
        rethrow;
      } on CalDavException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = CalDavException('$e');
      }
    }
    if (principal == null) {
      throw lastError ?? CalDavException('No CalDAV service found at $base');
    }

    final p = await _propfind(principal, '<c:calendar-home-set/>');
    final homeHref = p.map((r) => r.href(_caldav, 'calendar-home-set')).nonNulls.firstOrNull;
    if (homeHref == null) throw CalDavException('No calendar home for this account');
    final home = p.first.base.resolve(homeHref);
    return CalDavAccount(principal: principal, home: home, calendars: await listCalendars(home));
  }

  Future<List<CalDavCalendar>> listCalendars(Uri home) async {
    final responses = await _propfind(home, '''
<d:resourcetype/><d:displayname/><cs:getctag/><i:calendar-color/>
<d:current-user-privilege-set/><c:supported-calendar-component-set/>''', depth: 1);
    final result = <CalDavCalendar>[];
    for (final r in responses) {
      final type = r.prop(_dav, 'resourcetype');
      if (type == null || type.getElement('calendar', namespaceUri: _caldav) == null) continue;
      final comps = r.prop(_caldav, 'supported-calendar-component-set');
      if (comps != null) {
        final names = comps
            .findElements('comp', namespaceUri: _caldav)
            .map((c) => c.getAttribute('name')?.toUpperCase());
        if (!names.contains('VEVENT')) continue;
      }
      final privileges = r.prop(_dav, 'current-user-privilege-set');
      final writable = privileges == null ||
          privileges.findAllElements('*', namespaceUri: _dav).any(
              (e) => const {'write', 'write-content', 'all', 'bind'}.contains(e.name.local));
      final url = r.base.resolve(r.rawHref);
      final name = r.prop(_dav, 'displayname')?.innerText.trim();
      result.add(CalDavCalendar(
        url: url,
        displayName: (name == null || name.isEmpty)
            ? Uri.decodeComponent(url.pathSegments.where((s) => s.isNotEmpty).last)
            : name,
        color: _parseColor(r.prop(_apple, 'calendar-color')?.innerText),
        ctag: r.prop(_cs, 'getctag')?.innerText.trim(),
        readOnly: !writable,
      ));
    }
    return result;
  }

  static Color? _parseColor(String? value) {
    if (value == null) return null;
    final v = value.trim();
    if (!v.startsWith('#') || v.length < 7) return null;
    return parseHexColor(v.substring(0, 7));
  }

  /// Current change marker of a calendar.
  Future<String?> ctag(Uri calendar) async {
    final r = await _propfind(calendar, '<cs:getctag/>');
    return r.firstOrNull?.prop(_cs, 'getctag')?.innerText.trim();
  }

  // ---------------------------------------------------------------------------
  // Objects
  // ---------------------------------------------------------------------------

  /// Downloads every VEVENT resource of a calendar.
  Future<List<CalDavObject>> fetchEvents(Uri calendar) async {
    final r = await _send('REPORT', calendar, headers: {'Depth': '1'}, body: '''
<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"/></c:comp-filter></c:filter>
</c:calendar-query>''');
    if (r.response.statusCode != 207) {
      throw CalDavException('REPORT ${r.response.statusCode} on $calendar', statusCode: r.response.statusCode);
    }
    return [
      for (final resp in _parseMultistatus(r.url, r.response))
        if (resp.prop(_caldav, 'calendar-data') case final data?)
          CalDavObject(
            url: resp.base.resolve(resp.rawHref),
            etag: resp.prop(_dav, 'getetag')?.innerText.trim(),
            data: data.innerText,
          ),
    ];
  }

  /// Creates ([create]) or replaces a resource; returns the new ETag if the
  /// server sent one.
  Future<String?> put(Uri url, String ics, {String? ifMatch, bool create = false}) async {
    final r = await _send('PUT', url, body: ics, contentType: 'text/calendar; charset=utf-8', headers: {
      if (create) 'If-None-Match': '*',
      if (!create && ifMatch != null) 'If-Match': ifMatch,
    });
    final code = r.response.statusCode;
    if (code == 412) throw CalDavConflictException();
    if (code != 200 && code != 201 && code != 204) {
      throw CalDavException('PUT $code: ${_errorText(r.response)}', statusCode: code);
    }
    return r.response.headers['etag'];
  }

  Future<void> delete(Uri url, {String? ifMatch}) async {
    final r = await _send('DELETE', url, headers: {'If-Match': ?ifMatch});
    final code = r.response.statusCode;
    if (code == 412) throw CalDavConflictException();
    if (code == 404) return; // already gone
    if (code != 200 && code != 204) throw CalDavException('DELETE $code', statusCode: code);
  }

  /// Creates a calendar collection under [home].
  Future<Uri> makeCalendar(Uri home, String slug, String displayName, Color color) async {
    final url = home.resolve('${Uri.encodeComponent(slug)}/');
    final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final r = await _send('MKCALENDAR', url, body: '''
<?xml version="1.0" encoding="utf-8"?>
<c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:i="http://apple.com/ns/ical/">
  <d:set><d:prop>
    <d:displayname>${_xmlEscape(displayName)}</d:displayname>
    <i:calendar-color>$hex</i:calendar-color>
    <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>
  </d:prop></d:set>
</c:mkcalendar>''');
    if (r.response.statusCode != 201) {
      throw CalDavException('MKCALENDAR ${r.response.statusCode}', statusCode: r.response.statusCode);
    }
    return url;
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _errorText(http.Response r) {
    final body = r.body;
    return body.length > 200 ? body.substring(0, 200) : body;
  }

  void close() => _client.close();

  // ---------------------------------------------------------------------------
  // Multistatus parsing
  // ---------------------------------------------------------------------------

  static List<_DavResponse> _parseMultistatus(Uri base, http.Response response) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on XmlException catch (e) {
      throw CalDavException('Invalid XML response: ${e.message}');
    }
    return [
      for (final r in doc.findAllElements('response', namespaceUri: _dav))
        if (r.getElement('href', namespaceUri: _dav) case final href?)
          _DavResponse(
            base,
            href.innerText.trim(),
            [
              for (final ps in r.findElements('propstat', namespaceUri: _dav))
                if (ps.getElement('status', namespaceUri: _dav)?.innerText.contains(' 200') ?? false)
                  ...?ps.getElement('prop', namespaceUri: _dav)?.childElements,
            ],
          ),
    ];
  }
}

class _Response {
  _Response(this.url, this.response);
  final Uri url;
  final http.Response response;
}

class _DavResponse {
  _DavResponse(this.base, this.rawHref, this.props);

  final Uri base;
  final String rawHref;
  final List<XmlElement> props;

  XmlElement? prop(String ns, String name) =>
      props.where((p) => p.name.local == name && p.namespaceUri == ns).firstOrNull;

  /// Text of the DAV:href inside a property.
  String? href(String ns, String name) =>
      prop(ns, name)?.getElement('href', namespaceUri: _dav)?.innerText.trim();
}
