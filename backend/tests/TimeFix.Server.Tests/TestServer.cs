using System.Net.Http.Headers;
using System.Text;
using System.Xml.Linq;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using TimeFix.Server.Data;

namespace TimeFix.Server.Tests;

/// <summary>
/// Starts the server in memory with its own database: a temporary SQLite file
/// by default, or a fresh PostgreSQL database when TIMEFIX_TEST_POSTGRES holds
/// a connection string (e.g. "Host=localhost;Username=postgres;Password=…").
/// </summary>
public sealed class TimeFixFactory : WebApplicationFactory<Program>
{
    public const string AdminUser = "admin";
    public const string AdminPassword = "admin-password";

    private readonly string _sqlitePath = Path.Combine(Path.GetTempPath(), $"timefix-test-{Guid.NewGuid():N}.db");
    private readonly string? _postgres = Environment.GetEnvironmentVariable("TIMEFIX_TEST_POSTGRES");
    private readonly string _pgDatabase = $"timefix_test_{Guid.NewGuid():N}";

    public bool IsPostgres => !string.IsNullOrEmpty(_postgres);

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("Admin:Username", AdminUser);
        builder.UseSetting("Admin:Password", AdminPassword);
        builder.UseSetting("RateLimit:PermitsPerMinute", "100000");
        if (IsPostgres)
        {
            builder.UseSetting("Database:Provider", "Postgres");
            builder.UseSetting("Database:ConnectionString", $"{_postgres};Database={_pgDatabase}");
        }
        else
        {
            builder.UseSetting("Database:Provider", "Sqlite");
            builder.UseSetting("Database:ConnectionString", $"Data Source={_sqlitePath};Pooling=False");
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            try
            {
                using var scope = Services.CreateScope();
                scope.ServiceProvider.GetRequiredService<TimeFixDbContext>().Database.EnsureDeleted();
            }
            catch
            {
                // Best effort clean-up.
            }
        }
        base.Dispose(disposing);
        if (File.Exists(_sqlitePath)) File.Delete(_sqlitePath);
    }

    public HttpClient ClientFor(string user, string password)
    {
        var client = CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic",
            Convert.ToBase64String(Encoding.UTF8.GetBytes($"{user}:{password}")));
        return client;
    }

    public HttpClient AdminClient() => ClientFor(AdminUser, AdminPassword);
}

public static class Dav
{
    public static readonly XNamespace D = "DAV:";
    public static readonly XNamespace C = "urn:ietf:params:xml:ns:caldav";
    public static readonly XNamespace CS = "http://calendarserver.org/ns/";
    public static readonly XNamespace Apple = "http://apple.com/ns/ical/";

    public static async Task<HttpResponseMessage> SendAsync(this HttpClient client, string method, string path,
        string? body = null, string contentType = "application/xml; charset=utf-8",
        IDictionary<string, string>? headers = null)
    {
        var request = new HttpRequestMessage(new HttpMethod(method), path);
        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8);
            request.Content.Headers.ContentType = MediaTypeHeaderValue.Parse(contentType);
        }
        foreach (var (k, v) in headers ?? new Dictionary<string, string>())
        {
            request.Headers.TryAddWithoutValidation(k, v);
        }
        return await client.SendAsync(request);
    }

    public static async Task<XDocument> XmlAsync(this HttpResponseMessage response) =>
        XDocument.Parse(await response.Content.ReadAsStringAsync());

    /// <summary>Value of a property in the response for <paramref name="href"/> (200 propstat only).</summary>
    public static XElement? Prop(this XDocument doc, string href, XName name) =>
        doc.Root!.Elements(D + "response")
            .Where(r => r.Element(D + "href")!.Value == href)
            .Elements(D + "propstat")
            .Where(ps => ps.Element(D + "status")!.Value.Contains("200"))
            .Elements(D + "prop").Elements(name).FirstOrDefault();

    public static List<string> Hrefs(this XDocument doc) =>
        doc.Root!.Elements(D + "response").Select(r => r.Element(D + "href")!.Value).ToList();

    public static string Event(string uid, string start, string end, string summary = "Event", string? rrule = null) =>
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\n" +
        $"UID:{uid}\r\nDTSTAMP:20261101T000000Z\r\nDTSTART:{start}\r\nDTEND:{end}\r\nSUMMARY:{summary}\r\n" +
        (rrule is null ? "" : $"RRULE:{rrule}\r\n") +
        "END:VEVENT\r\nEND:VCALENDAR\r\n";

    public static Task<HttpResponseMessage> PutEventAsync(this HttpClient client, string path, string ics,
        IDictionary<string, string>? headers = null) =>
        client.SendAsync("PUT", path, ics, "text/calendar; charset=utf-8", headers);
}
