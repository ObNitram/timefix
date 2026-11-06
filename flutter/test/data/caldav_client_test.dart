import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timefix/data/caldav/caldav_client.dart';

http.Response _xml(String body, {int status = 207}) =>
    http.Response.bytes(body.codeUnits, status, headers: {'content-type': 'application/xml'});

void main() {
  test('discovery follows the well-known redirect and lists VEVENT calendars', () async {
    final requests = <String>[];
    final client = MockClient((r) async {
      requests.add('${r.method} ${r.url.path}');
      expect(r.headers['Authorization'], startsWith('Basic '));
      switch ((r.method, r.url.path)) {
        case ('PROPFIND', '/'):
          return http.Response('', 404);
        case ('PROPFIND', '/.well-known/caldav'):
          return http.Response('', 301, headers: {'location': '/remote.php/dav/'});
        case ('PROPFIND', '/remote.php/dav/'):
          return _xml('''<d:multistatus xmlns:d="DAV:"><d:response><d:href>/remote.php/dav/</d:href>
            <d:propstat><d:prop><d:current-user-principal><d:href>/remote.php/dav/principals/users/bob/</d:href>
            </d:current-user-principal></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>''');
        case ('PROPFIND', '/remote.php/dav/principals/users/bob/'):
          return _xml('''<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><response>
            <href>/remote.php/dav/principals/users/bob/</href><propstat><prop><C:calendar-home-set>
            <href>https://cloud.example.com/remote.php/dav/calendars/bob/</href></C:calendar-home-set></prop>
            <status>HTTP/1.1 200 OK</status></propstat></response></multistatus>''');
        case ('PROPFIND', '/remote.php/dav/calendars/bob/'):
          expect(r.headers['Depth'], '1');
          return _xml('''<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"
              xmlns:cs="http://calendarserver.org/ns/" xmlns:x="http://apple.com/ns/ical/">
            <d:response><d:href>/remote.php/dav/calendars/bob/</d:href><d:propstat><d:prop>
              <d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
            <d:response><d:href>/remote.php/dav/calendars/bob/personal/</d:href><d:propstat><d:prop>
              <d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>Perso</d:displayname>
              <cs:getctag>42</cs:getctag><x:calendar-color>#33B679FF</x:calendar-color>
              <c:supported-calendar-component-set><c:comp name="VEVENT"/><c:comp name="VTODO"/></c:supported-calendar-component-set>
              <d:current-user-privilege-set><d:privilege><d:all/></d:privilege></d:current-user-privilege-set>
              </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
              <d:propstat><d:prop><d:sync-token/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>
            <d:response><d:href>/remote.php/dav/calendars/bob/tasks/</d:href><d:propstat><d:prop>
              <d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>Tâches</d:displayname>
              <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
              </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
            <d:response><d:href>/remote.php/dav/calendars/bob/shared/</d:href><d:propstat><d:prop>
              <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
              <d:current-user-privilege-set><d:privilege><d:read/></d:privilege></d:current-user-privilege-set>
              </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          </d:multistatus>''');
      }
      return http.Response('unexpected ${r.method} ${r.url}', 500);
    });

    final caldav = CalDavClient(username: 'bob', password: 'pw', client: client);
    final account = await caldav.discover('cloud.example.com');
    expect(account.home.toString(), 'https://cloud.example.com/remote.php/dav/calendars/bob/');
    expect(account.calendars.map((c) => c.displayName), ['Perso', 'shared']);
    final perso = account.calendars.first;
    expect(perso.url.toString(), 'https://cloud.example.com/remote.php/dav/calendars/bob/personal/');
    expect(perso.ctag, '42');
    expect(perso.readOnly, isFalse);
    expect(perso.color!.toARGB32(), 0xFF33B679);
    expect(account.calendars.last.readOnly, isTrue);
    expect(requests.first, 'PROPFIND /');
  });

  test('status codes map to typed errors', () async {
    final client = MockClient((r) async => switch (r.method) {
          'PUT' => http.Response('', 412),
          'DELETE' => http.Response('', 404),
          _ => http.Response('', 401),
        });
    final caldav = CalDavClient(username: 'u', password: 'p', client: client);
    final url = Uri.parse('https://x.example/cal/a.ics');
    await expectLater(caldav.put(url, 'x', ifMatch: '"1"'), throwsA(isA<CalDavConflictException>()));
    await caldav.delete(url); // 404: already gone, no error
    await expectLater(caldav.discover('https://x.example'), throwsA(isA<CalDavAuthException>()));
  });

  test('normalizes server URLs', () {
    expect(CalDavClient.normalizeServerUrl('cal.example.com').toString(), 'https://cal.example.com/');
    expect(CalDavClient.normalizeServerUrl('http://10.0.2.2:8080').toString(), 'http://10.0.2.2:8080/');
    expect(() => CalDavClient.normalizeServerUrl('ftp://x'), throwsA(isA<CalDavException>()));
  });
}
