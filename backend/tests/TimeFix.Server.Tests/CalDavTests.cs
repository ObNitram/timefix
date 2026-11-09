using System.Net;
using System.Net.Http.Json;
using static TimeFix.Server.Tests.Dav;

namespace TimeFix.Server.Tests;

public class CalDavTests : IDisposable
{
    private readonly TimeFixFactory _factory = new();
    private readonly HttpClient _admin;
    private const string Cal = "/dav/calendars/admin/default/";

    public CalDavTests() => _admin = _factory.AdminClient();

    public void Dispose() => _factory.Dispose();

    [Fact]
    public async Task Requests_without_valid_credentials_are_rejected()
    {
        var anonymous = _factory.CreateClient();
        var r = await anonymous.SendAsync("PROPFIND", "/dav/");
        Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode);
        Assert.Contains("Basic", r.Headers.WwwAuthenticate.ToString());

        var wrong = _factory.ClientFor("admin", "nope");
        Assert.Equal(HttpStatusCode.Unauthorized, (await wrong.SendAsync("PROPFIND", "/dav/")).StatusCode);
    }

    [Fact]
    public async Task Well_known_redirects_to_dav_root_and_options_advertise_caldav()
    {
        var r = await _admin.GetAsync("/.well-known/caldav");
        Assert.Equal(HttpStatusCode.MovedPermanently, r.StatusCode);
        Assert.Equal("/dav/", r.Headers.Location!.OriginalString);

        var options = await _factory.CreateClient().SendAsync("OPTIONS", "/dav/");
        Assert.Contains("calendar-access", options.Headers.GetValues("DAV").Single());
    }

    [Fact]
    public async Task Discovery_principal_home_and_calendars()
    {
        const string propfind = """
            <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
              <d:prop><d:current-user-principal/><c:calendar-home-set/></d:prop>
            </d:propfind>
            """;
        var root = await (await _admin.SendAsync("PROPFIND", "/dav/", propfind,
            headers: new Dictionary<string, string> { ["Depth"] = "0" })).XmlAsync();
        Assert.Equal("/dav/principals/admin/", root.Prop("/dav/", D + "current-user-principal")!.Value);

        var principal = await (await _admin.SendAsync("PROPFIND", "/dav/principals/admin/", propfind,
            headers: new Dictionary<string, string> { ["Depth"] = "0" })).XmlAsync();
        Assert.Equal("/dav/calendars/admin/",
            principal.Prop("/dav/principals/admin/", C + "calendar-home-set")!.Value);

        var homeResponse = await _admin.SendAsync("PROPFIND", "/dav/calendars/admin/", """
            <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/" xmlns:i="http://apple.com/ns/ical/">
              <d:prop><d:resourcetype/><d:displayname/><cs:getctag/><i:calendar-color/><d:current-user-privilege-set/></d:prop>
            </d:propfind>
            """, headers: new Dictionary<string, string> { ["Depth"] = "1" });
        Assert.Equal(207, (int)homeResponse.StatusCode);
        var home = await homeResponse.XmlAsync();
        Assert.Contains(Cal, home.Hrefs());
        Assert.NotNull(home.Prop(Cal, D + "resourcetype")!.Element(C + "calendar"));
        Assert.Equal("Personnel", home.Prop(Cal, D + "displayname")!.Value);
        Assert.Equal("#039BE5", home.Prop(Cal, Apple + "calendar-color")!.Value);
        Assert.StartsWith("ctag-", home.Prop(Cal, CS + "getctag")!.Value);
        Assert.Contains(home.Prop(Cal, D + "current-user-privilege-set")!.Descendants(D + "write"), _ => true);
    }

    [Fact]
    public async Task Object_lifecycle_with_etags()
    {
        var path = Cal + "event1.ics";
        var ics = Event("uid-1", "20261110T090000Z", "20261110T100000Z", "Réunion");
        var ctag0 = await CtagAsync();

        var created = await _admin.PutEventAsync(path, ics, new Dictionary<string, string> { ["If-None-Match"] = "*" });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var etag = created.Headers.ETag!.Tag;

        var again = await _admin.PutEventAsync(path, ics, new Dictionary<string, string> { ["If-None-Match"] = "*" });
        Assert.Equal(HttpStatusCode.PreconditionFailed, again.StatusCode);

        var get = await _admin.GetAsync(path);
        Assert.Equal(HttpStatusCode.OK, get.StatusCode);
        Assert.Equal(etag, get.Headers.ETag!.Tag);
        Assert.Contains("SUMMARY:Réunion", await get.Content.ReadAsStringAsync());

        var updatedIcs = ics.Replace("Réunion", "Réunion modifiée");
        var stale = await _admin.PutEventAsync(path, updatedIcs, new Dictionary<string, string> { ["If-Match"] = "\"stale\"" });
        Assert.Equal(HttpStatusCode.PreconditionFailed, stale.StatusCode);
        var updated = await _admin.PutEventAsync(path, updatedIcs, new Dictionary<string, string> { ["If-Match"] = etag });
        Assert.Equal(HttpStatusCode.NoContent, updated.StatusCode);
        Assert.NotEqual(etag, updated.Headers.ETag!.Tag);
        Assert.NotEqual(ctag0, await CtagAsync());

        var badDelete = await _admin.SendAsync("DELETE", path, headers: new Dictionary<string, string> { ["If-Match"] = etag });
        Assert.Equal(HttpStatusCode.PreconditionFailed, badDelete.StatusCode);
        var delete = await _admin.SendAsync("DELETE", path,
            headers: new Dictionary<string, string> { ["If-Match"] = updated.Headers.ETag!.Tag });
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await _admin.GetAsync(path)).StatusCode);
    }

    [Fact]
    public async Task Invalid_data_and_uid_conflicts_are_rejected()
    {
        var invalid = await _admin.PutEventAsync(Cal + "bad.ics", "hello");
        Assert.Equal(HttpStatusCode.Forbidden, invalid.StatusCode);
        Assert.Contains("valid-calendar-data", await invalid.Content.ReadAsStringAsync());

        var noUid = await _admin.PutEventAsync(Cal + "nouid.ics",
            "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20261110T090000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
        Assert.Equal(HttpStatusCode.Forbidden, noUid.StatusCode);

        await _admin.PutEventAsync(Cal + "a.ics", Event("same", "20261110T090000Z", "20261110T100000Z"));
        var conflict = await _admin.PutEventAsync(Cal + "b.ics", Event("same", "20261111T090000Z", "20261111T100000Z"));
        Assert.Equal(HttpStatusCode.Forbidden, conflict.StatusCode);
        var body = await conflict.Content.ReadAsStringAsync();
        Assert.Contains("no-uid-conflict", body);
        Assert.Contains(Cal + "a.ics", body);

        var json = await _admin.PutEventAsync(Cal + "c.ics", "{}", new Dictionary<string, string>());
        Assert.Equal(HttpStatusCode.Forbidden, json.StatusCode);
    }

    [Fact]
    public async Task Calendar_query_filters_by_component_and_time_range()
    {
        await _admin.PutEventAsync(Cal + "nov.ics", Event("nov", "20261110T090000Z", "20261110T100000Z", "Novembre"));
        await _admin.PutEventAsync(Cal + "jan.ics", Event("jan", "20270115T090000Z", "20270115T100000Z", "Janvier"));
        await _admin.PutEventAsync(Cal + "weekly.ics",
            Event("weekly", "20250106T080000Z", "20250106T083000Z", "Hebdo", "FREQ=WEEKLY"));
        await _admin.PutEventAsync(Cal + "ended.ics",
            Event("ended", "20250106T080000Z", "20250106T083000Z", "Fini", "FREQ=DAILY;UNTIL=20250110T080000Z"));
        await _admin.PutEventAsync(Cal + "tz.ics",
            "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:tz\r\nDTSTART;TZID=Europe/Paris:20261201T235000\r\n" +
            "DURATION:PT20M\r\nSUMMARY:Tz\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");

        async Task<List<string>> Query(string start, string end, string component = "VEVENT")
        {
            var r = await _admin.SendAsync("REPORT", Cal, $"""
                <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
                  <d:prop><d:getetag/><c:calendar-data/></d:prop>
                  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="{component}">
                    <c:time-range start="{start}" end="{end}"/>
                  </c:comp-filter></c:comp-filter></c:filter>
                </c:calendar-query>
                """, headers: new Dictionary<string, string> { ["Depth"] = "1" });
            Assert.Equal(207, (int)r.StatusCode);
            var doc = await r.XmlAsync();
            foreach (var href in doc.Hrefs())
            {
                Assert.Contains("BEGIN:VCALENDAR", doc.Prop(href, C + "calendar-data")!.Value);
                Assert.NotNull(doc.Prop(href, D + "getetag"));
            }
            return doc.Hrefs().Select(h => h[Cal.Length..]).Order().ToList();
        }

        Assert.Equal(["nov.ics", "weekly.ics"], await Query("20261101T000000Z", "20261130T000000Z"));
        Assert.Equal(["tz.ics", "weekly.ics"], await Query("20261201T000000Z", "20261231T000000Z"));
        Assert.Equal(["ended.ics", "weekly.ics"], await Query("20250101T000000Z", "20250201T000000Z"));
        Assert.Empty(await Query("20261101T000000Z", "20261130T000000Z", "VTODO"));
    }

    [Fact]
    public async Task Calendar_multiget_returns_requested_objects()
    {
        await _admin.PutEventAsync(Cal + "one.ics", Event("one", "20261110T090000Z", "20261110T100000Z"));
        await _admin.PutEventAsync(Cal + "two.ics", Event("two", "20261111T090000Z", "20261111T100000Z"));
        var r = await _admin.SendAsync("REPORT", Cal, $"""
            <c:calendar-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
              <d:prop><d:getetag/><c:calendar-data/></d:prop>
              <d:href>{Cal}one.ics</d:href>
              <d:href>http://localhost{Cal}two.ics</d:href>
              <d:href>{Cal}missing.ics</d:href>
              <d:href>/dav/calendars/someone-else/default/x.ics</d:href>
            </c:calendar-multiget>
            """);
        var doc = await r.XmlAsync();
        Assert.Contains("UID:one", doc.Prop(Cal + "one.ics", C + "calendar-data")!.Value);
        Assert.Contains("UID:two", doc.Prop(Cal + "two.ics", C + "calendar-data")!.Value);
        var statuses = doc.Root!.Elements(D + "response")
            .Where(e => e.Element(D + "status") is not null)
            .Select(e => e.Element(D + "status")!.Value).ToList();
        Assert.Equal(2, statuses.Count);
        Assert.All(statuses, s => Assert.Contains("404", s));
    }

    [Fact]
    public async Task Unsupported_report_is_rejected()
    {
        var r = await _admin.SendAsync("REPORT", Cal,
            """<d:sync-collection xmlns:d="DAV:"><d:sync-token/><d:prop><d:getetag/></d:prop></d:sync-collection>""");
        Assert.Equal(HttpStatusCode.Forbidden, r.StatusCode);
    }

    [Fact]
    public async Task Mkcalendar_proppatch_and_delete_collection()
    {
        var mk = await _admin.SendAsync("MKCALENDAR", "/dav/calendars/admin/work/", """
            <c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:i="http://apple.com/ns/ical/">
              <d:set><d:prop><d:displayname>Travail</d:displayname><i:calendar-color>#33B679</i:calendar-color></d:prop></d:set>
            </c:mkcalendar>
            """);
        Assert.Equal(HttpStatusCode.Created, mk.StatusCode);
        Assert.Equal(HttpStatusCode.MethodNotAllowed,
            (await _admin.SendAsync("MKCALENDAR", "/dav/calendars/admin/work/")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await _admin.SendAsync("MKCALENDAR", "/dav/calendars/admin/.hidden/")).StatusCode);

        var patch = await _admin.SendAsync("PROPPATCH", "/dav/calendars/admin/work/", """
            <d:propertyupdate xmlns:d="DAV:" xmlns:i="http://apple.com/ns/ical/">
              <d:set><d:prop><d:displayname>Boulot</d:displayname><i:calendar-color>#D50000</i:calendar-color></d:prop></d:set>
            </d:propertyupdate>
            """);
        Assert.Equal(207, (int)patch.StatusCode);
        Assert.DoesNotContain("403", await patch.Content.ReadAsStringAsync());

        var badPatch = await _admin.SendAsync("PROPPATCH", "/dav/calendars/admin/work/", """
            <d:propertyupdate xmlns:d="DAV:" xmlns:i="http://apple.com/ns/ical/">
              <d:set><d:prop><d:displayname>Ignoré</d:displayname><i:calendar-color>red</i:calendar-color></d:prop></d:set>
            </d:propertyupdate>
            """);
        var badBody = await badPatch.Content.ReadAsStringAsync();
        Assert.Contains("403", badBody);
        Assert.Contains("424", badBody);

        var doc = await (await _admin.SendAsync("PROPFIND", "/dav/calendars/admin/work/",
            """<d:propfind xmlns:d="DAV:" xmlns:i="http://apple.com/ns/ical/"><d:prop><d:displayname/><i:calendar-color/></d:prop></d:propfind>""",
            headers: new Dictionary<string, string> { ["Depth"] = "0" })).XmlAsync();
        Assert.Equal("Boulot", doc.Prop("/dav/calendars/admin/work/", D + "displayname")!.Value);
        Assert.Equal("#D50000", doc.Prop("/dav/calendars/admin/work/", Apple + "calendar-color")!.Value);

        await _admin.PutEventAsync("/dav/calendars/admin/work/x.ics", Event("x", "20261110T090000Z", "20261110T100000Z"));
        Assert.Equal(HttpStatusCode.NoContent, (await _admin.SendAsync("DELETE", "/dav/calendars/admin/work/")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,
            (await _admin.SendAsync("PROPFIND", "/dav/calendars/admin/work/")).StatusCode);
    }

    [Fact]
    public async Task Get_on_calendar_exports_a_single_ics()
    {
        await _admin.PutEventAsync(Cal + "e1.ics", Event("e1", "20261110T090000Z", "20261110T100000Z", "Un"));
        await _admin.PutEventAsync(Cal + "e2.ics", Event("e2", "20261111T090000Z", "20261111T100000Z", "Deux"));
        var text = await (await _admin.GetAsync(Cal)).Content.ReadAsStringAsync();
        Assert.StartsWith("BEGIN:VCALENDAR", text);
        Assert.Equal(2, text.Split("BEGIN:VEVENT").Length - 1);
        Assert.Equal(1, text.Split("BEGIN:VCALENDAR").Length - 1);
        Assert.Contains("X-WR-CALNAME:Personnel", text);
    }

    [Fact]
    public async Task Users_cannot_see_each_other()
    {
        var create = await _admin.PostAsJsonAsync("/api/admin/users",
            new { username = "bob", password = "bob-password", isAdmin = false });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var bob = _factory.ClientFor("bob", "bob-password");

        Assert.Equal(HttpStatusCode.NotFound, (await bob.SendAsync("PROPFIND", "/dav/calendars/admin/")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await bob.GetAsync(Cal)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,
            (await bob.PutEventAsync(Cal + "intrusion.ics", Event("i", "20261110T090000Z", "20261110T100000Z"))).StatusCode);
        Assert.Equal(207, (int)(await bob.SendAsync("PROPFIND", "/dav/calendars/bob/default/")).StatusCode);
    }

    private async Task<string> CtagAsync()
    {
        var doc = await (await _admin.SendAsync("PROPFIND", Cal,
            """<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/"><d:prop><cs:getctag/></d:prop></d:propfind>""",
            headers: new Dictionary<string, string> { ["Depth"] = "0" })).XmlAsync();
        return doc.Prop(Cal, CS + "getctag")!.Value;
    }
}
