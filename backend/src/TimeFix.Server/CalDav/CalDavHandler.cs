using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.EntityFrameworkCore;
using TimeFix.Server.Auth;
using TimeFix.Server.Data;

namespace TimeFix.Server.CalDav;

/// <summary>
/// CalDAV server (RFC 4791 subset over WebDAV RFC 4918).
///
/// Layout:
///   /dav/principals/{user}/             principal (calendar-home-set)
///   /dav/calendars/{user}/              calendar home (list of calendars)
///   /dav/calendars/{user}/{calendar}/   calendar collection
///   /dav/calendars/{user}/{calendar}/{name}.ics   calendar object
/// Users only see their own resources.
/// </summary>
public partial class CalDavHandler(TimeFixDbContext db, ILogger<CalDavHandler> logger, IConfiguration config)
{
    public static readonly string[] Methods =
        ["PROPFIND", "PROPPATCH", "MKCALENDAR", "REPORT", "GET", "HEAD", "PUT", "DELETE"];

    public const string AllowHeader =
        "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, MKCALENDAR, REPORT";

    public const string DavHeader = "1, 3, calendar-access";

    private long MaxResourceSize => config.GetValue("CalDav:MaxResourceSize", 1_000_000L);

    private sealed record Res(string Href, DavResourceKind Kind, Calendar? Calendar = null, CalendarObject? Object = null);

    private User _user = null!;
    private string _base = "";

    public static Task Options(HttpContext ctx)
    {
        ctx.Response.Headers.Allow = AllowHeader;
        ctx.Response.Headers["DAV"] = DavHeader;
        ctx.Response.StatusCode = StatusCodes.Status200OK;
        return Task.CompletedTask;
    }

    public async Task HandleAsync(HttpContext ctx, string? path)
    {
        var user = await db.Users.FindAsync(ctx.User.UserId());
        if (user is null)
        {
            ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }
        _user = user;
        _base = ctx.Request.PathBase.Value ?? "";
        ctx.Response.Headers["DAV"] = DavHeader;

        var p = DavPath.Parse(path);
        if (p.Kind == DavResourceKind.Unknown || (p.User is not null && p.User != user.Username))
        {
            ctx.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }

        try
        {
            switch (ctx.Request.Method)
            {
                case "PROPFIND": await PropfindAsync(ctx, p); break;
                case "PROPPATCH": await ProppatchAsync(ctx, p); break;
                case "MKCALENDAR": await MkcalendarAsync(ctx, p); break;
                case "REPORT": await ReportAsync(ctx, p); break;
                case "GET": await GetAsync(ctx, p, includeBody: true); break;
                case "HEAD": await GetAsync(ctx, p, includeBody: false); break;
                case "PUT": await PutAsync(ctx, p); break;
                case "DELETE": await DeleteAsync(ctx, p); break;
                default:
                    ctx.Response.Headers.Allow = AllowHeader;
                    ctx.Response.StatusCode = StatusCodes.Status405MethodNotAllowed;
                    break;
            }
        }
        catch (BadRequestException e)
        {
            ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
            await ctx.Response.WriteAsync(e.Message);
        }
    }

    // -------------------------------------------------------------------------
    // Resource resolution
    // -------------------------------------------------------------------------

    private string PrincipalHref => DavPath.PrincipalHref(_base, _user.Username);
    private string HomeHref => DavPath.HomeHref(_base, _user.Username);
    private string CalendarHref(Calendar c) => DavPath.CalendarHref(_base, _user.Username, c.Slug);
    private string ObjectHref(Calendar c, CalendarObject o) => DavPath.ObjectHref(_base, _user.Username, c.Slug, o.Name);

    private Task<Calendar?> FindCalendarAsync(string slug) =>
        db.Calendars.FirstOrDefaultAsync(c => c.OwnerId == _user.Id && c.Slug == slug);

    private Task<CalendarObject?> FindObjectAsync(Calendar cal, string name) =>
        db.CalendarObjects.FirstOrDefaultAsync(o => o.CalendarId == cal.Id && o.Name == name);

    private async Task<Res?> ResolveAsync(DavPath p)
    {
        switch (p.Kind)
        {
            case DavResourceKind.Root: return new Res(_base + DavPath.Prefix + "/", p.Kind);
            case DavResourceKind.Principals: return new Res(_base + DavPath.Prefix + "/principals/", p.Kind);
            case DavResourceKind.Calendars: return new Res(_base + DavPath.Prefix + "/calendars/", p.Kind);
            case DavResourceKind.Principal: return new Res(PrincipalHref, p.Kind);
            case DavResourceKind.CalendarHome: return new Res(HomeHref, p.Kind);
            case DavResourceKind.Calendar:
            {
                var cal = await FindCalendarAsync(p.Calendar!);
                return cal is null ? null : new Res(CalendarHref(cal), p.Kind, cal);
            }
            case DavResourceKind.Object:
            {
                var cal = await FindCalendarAsync(p.Calendar!);
                if (cal is null) return null;
                var obj = await FindObjectAsync(cal, p.Object!);
                return obj is null ? null : new Res(ObjectHref(cal, obj), p.Kind, cal, obj);
            }
            default: return null;
        }
    }

    private async Task<List<Res>> ChildrenAsync(Res r)
    {
        switch (r.Kind)
        {
            case DavResourceKind.Root:
                return [new Res(PrincipalHref, DavResourceKind.Principal), new Res(HomeHref, DavResourceKind.CalendarHome)];
            case DavResourceKind.Principals:
                return [new Res(PrincipalHref, DavResourceKind.Principal)];
            case DavResourceKind.Calendars:
                return [new Res(HomeHref, DavResourceKind.CalendarHome)];
            case DavResourceKind.CalendarHome:
                var cals = await db.Calendars.Where(c => c.OwnerId == _user.Id).OrderBy(c => c.Id).ToListAsync();
                return cals.Select(c => new Res(CalendarHref(c), DavResourceKind.Calendar, c)).ToList();
            case DavResourceKind.Calendar:
                var objs = await db.CalendarObjects.Where(o => o.CalendarId == r.Calendar!.Id)
                    .OrderBy(o => o.Id).ToListAsync();
                return objs.Select(o => new Res(ObjectHref(r.Calendar!, o), DavResourceKind.Object, r.Calendar, o)).ToList();
            default:
                return [];
        }
    }

    // -------------------------------------------------------------------------
    // Properties
    // -------------------------------------------------------------------------

    private static readonly XName[] AllProps =
    [
        Ns.Dav + "resourcetype", Ns.Dav + "displayname", Ns.Dav + "getetag", Ns.Dav + "getcontenttype",
        Ns.Dav + "getcontentlength", Ns.Dav + "getlastmodified", Ns.CalServer + "getctag",
        Ns.Apple + "calendar-color", Ns.CalDav + "calendar-description",
        Ns.CalDav + "supported-calendar-component-set",
    ];

    private XElement Href(string href) => new(Ns.Dav + "href", href);

    /// <summary>Returns the property value, or null when the resource does not have it.</summary>
    private XElement? GetProperty(Res r, XName name)
    {
        var cal = r.Calendar;
        var obj = r.Object;
        var isCollection = r.Kind != DavResourceKind.Object;

        if (name == Ns.Dav + "resourcetype")
        {
            var e = new XElement(name);
            if (isCollection) e.Add(new XElement(Ns.Dav + "collection"));
            if (r.Kind == DavResourceKind.Principal) e.Add(new XElement(Ns.Dav + "principal"));
            if (r.Kind == DavResourceKind.Calendar) e.Add(new XElement(Ns.CalDav + "calendar"));
            return e;
        }
        if (name == Ns.Dav + "displayname")
        {
            return r.Kind switch
            {
                DavResourceKind.Root => new XElement(name, "TimeFix"),
                DavResourceKind.Principal or DavResourceKind.CalendarHome => new XElement(name, _user.Username),
                DavResourceKind.Calendar => new XElement(name, cal!.DisplayName),
                _ => null,
            };
        }
        if (name == Ns.Dav + "current-user-principal") return new XElement(name, Href(PrincipalHref));
        if (name == Ns.Dav + "principal-URL" && r.Kind == DavResourceKind.Principal)
            return new XElement(name, Href(PrincipalHref));
        if (name == Ns.Dav + "owner" && r.Kind is DavResourceKind.CalendarHome or DavResourceKind.Calendar or DavResourceKind.Object)
            return new XElement(name, Href(PrincipalHref));
        if (name == Ns.CalDav + "calendar-home-set" && r.Kind == DavResourceKind.Principal)
            return new XElement(name, Href(HomeHref));
        if (name == Ns.Dav + "current-user-privilege-set")
        {
            string[] privileges = ["read", "read-current-user-privilege-set", "write", "write-properties",
                "write-content", "bind", "unbind"];
            return new XElement(name, privileges.Select(p =>
                new XElement(Ns.Dav + "privilege", new XElement(Ns.Dav + p))));
        }
        if (name == Ns.Dav + "supported-report-set" && r.Kind is DavResourceKind.Calendar or DavResourceKind.Object)
        {
            return new XElement(name,
                new XElement(Ns.Dav + "supported-report", new XElement(Ns.Dav + "report", new XElement(Ns.CalDav + "calendar-query"))),
                new XElement(Ns.Dav + "supported-report", new XElement(Ns.Dav + "report", new XElement(Ns.CalDav + "calendar-multiget"))));
        }

        if (cal is not null && r.Kind == DavResourceKind.Calendar)
        {
            if (name == Ns.CalServer + "getctag") return new XElement(name, CTagValue(cal));
            if (name == Ns.Dav + "getetag") return new XElement(name, $"\"{CTagValue(cal)}\"");
            if (name == Ns.CalDav + "calendar-description")
                return cal.Description is null ? null : new XElement(name, cal.Description);
            if (name == Ns.Apple + "calendar-color") return cal.Color is null ? null : new XElement(name, cal.Color);
            if (name == Ns.CalDav + "supported-calendar-component-set")
                return new XElement(name, new[] { "VEVENT", "VTODO", "VJOURNAL" }
                    .Select(c => new XElement(Ns.CalDav + "comp", new XAttribute("name", c))));
            if (name == Ns.CalDav + "supported-calendar-data")
                return new XElement(name, new XElement(Ns.CalDav + "calendar-data",
                    new XAttribute("content-type", "text/calendar"), new XAttribute("version", "2.0")));
            if (name == Ns.CalDav + "max-resource-size") return new XElement(name, MaxResourceSize);
        }

        if (obj is not null)
        {
            if (name == Ns.Dav + "getetag") return new XElement(name, obj.ETag);
            if (name == Ns.Dav + "getcontenttype")
                return new XElement(name, $"text/calendar; charset=utf-8; component={obj.ComponentType.ToLowerInvariant()}");
            if (name == Ns.Dav + "getcontentlength") return new XElement(name, Encoding.UTF8.GetByteCount(obj.Data));
            if (name == Ns.Dav + "getlastmodified") return new XElement(name, obj.LastModified.ToString("R"));
            if (name == Ns.CalDav + "calendar-data") return new XElement(name, obj.Data);
        }
        return null;
    }

    private static string CTagValue(Calendar c) => $"ctag-{c.CTag}";

    private enum PropMode { Prop, AllProp, PropName }

    private static (PropMode Mode, List<XName> Names) ParsePropRequest(XElement? container)
    {
        if (container is null) return (PropMode.AllProp, []);
        if (container.Element(Ns.Dav + "propname") is not null) return (PropMode.PropName, []);
        var prop = container.Element(Ns.Dav + "prop");
        if (prop is null) return (PropMode.AllProp, []);
        return (PropMode.Prop, prop.Elements().Select(e => e.Name).ToList());
    }

    private XElement BuildResponse(Res r, PropMode mode, IReadOnlyList<XName> names)
    {
        var props = new List<(XElement, int)>();
        switch (mode)
        {
            case PropMode.AllProp:
                foreach (var n in AllProps)
                {
                    var v = GetProperty(r, n);
                    if (v is not null) props.Add((v, 200));
                }
                break;
            case PropMode.PropName:
                foreach (var n in AllProps)
                {
                    if (GetProperty(r, n) is not null) props.Add((new XElement(n), 200));
                }
                break;
            default:
                foreach (var n in names)
                {
                    var v = GetProperty(r, n);
                    props.Add(v is null ? (new XElement(n), 404) : (v, 200));
                }
                break;
        }
        return DavXml.Response(r.Href, props);
    }

    // -------------------------------------------------------------------------
    // PROPFIND
    // -------------------------------------------------------------------------

    private async Task PropfindAsync(HttpContext ctx, DavPath p)
    {
        var res = await ResolveAsync(p);
        if (res is null)
        {
            ctx.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }
        var doc = await DavXml.ReadBodyAsync(ctx.Request);
        if (doc?.Root is { } root && root.Name != Ns.Dav + "propfind")
            throw new BadRequestException("Expected DAV:propfind");
        var (mode, names) = ParsePropRequest(doc?.Root);

        var depth = ctx.Request.Headers["Depth"].ToString();
        var resources = new List<Res> { res };
        if (depth != "0") resources.AddRange(await ChildrenAsync(res));

        await DavXml.WriteAsync(ctx.Response, 207,
            DavXml.Multistatus(resources.Select(r => BuildResponse(r, mode, names))));
    }

    // -------------------------------------------------------------------------
    // PROPPATCH (calendar collections)
    // -------------------------------------------------------------------------

    [GeneratedRegex("^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")]
    private static partial Regex ColorRegex();

    private static readonly HashSet<XName> WritableProps =
    [
        Ns.Dav + "displayname", Ns.CalDav + "calendar-description", Ns.Apple + "calendar-color",
        Ns.Apple + "calendar-order",
    ];

    private async Task ProppatchAsync(HttpContext ctx, DavPath p)
    {
        var res = await ResolveAsync(p);
        if (res is null)
        {
            ctx.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }
        var doc = await DavXml.ReadBodyAsync(ctx.Request);
        if (doc?.Root is not { } root || root.Name != Ns.Dav + "propertyupdate")
            throw new BadRequestException("Expected DAV:propertyupdate");

        var updates = new List<(XElement Prop, bool Remove)>();
        foreach (var op in root.Elements())
        {
            var remove = op.Name == Ns.Dav + "remove";
            if (!remove && op.Name != Ns.Dav + "set") continue;
            foreach (var prop in op.Elements(Ns.Dav + "prop").Elements()) updates.Add((prop, remove));
        }

        bool Valid((XElement Prop, bool Remove) u) =>
            res.Kind == DavResourceKind.Calendar && WritableProps.Contains(u.Prop.Name) &&
            (u.Remove || u.Prop.Name != Ns.Apple + "calendar-color" || ColorRegex().IsMatch(u.Prop.Value.Trim())) &&
            (u.Remove || u.Prop.Name != Ns.Dav + "displayname" || u.Prop.Value.Trim().Length is > 0 and <= 256);

        var allValid = updates.All(Valid);
        if (allValid)
        {
            var cal = res.Calendar!;
            foreach (var (prop, remove) in updates)
            {
                var value = prop.Value.Trim();
                if (prop.Name == Ns.Dav + "displayname") cal.DisplayName = remove ? cal.Slug : value;
                else if (prop.Name == Ns.CalDav + "calendar-description") cal.Description = remove ? null : value;
                else if (prop.Name == Ns.Apple + "calendar-color") cal.Color = remove ? null : value;
            }
            cal.CTag++;
            await db.SaveChangesAsync();
        }

        var statuses = updates.Select(u => (new XElement(u.Prop.Name), allValid ? 200 : Valid(u) ? 424 : 403));
        await DavXml.WriteAsync(ctx.Response, 207, DavXml.Multistatus([DavXml.Response(res.Href, statuses)]));
    }

    // -------------------------------------------------------------------------
    // MKCALENDAR
    // -------------------------------------------------------------------------

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")]
    private static partial Regex SlugRegex();

    private async Task MkcalendarAsync(HttpContext ctx, DavPath p)
    {
        if (p.Kind != DavResourceKind.Calendar || !SlugRegex().IsMatch(p.Calendar!))
        {
            ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
            return;
        }
        if (await FindCalendarAsync(p.Calendar!) is not null)
        {
            ctx.Response.Headers.Allow = AllowHeader;
            ctx.Response.StatusCode = StatusCodes.Status405MethodNotAllowed;
            return;
        }
        var cal = new Calendar { OwnerId = _user.Id, Slug = p.Calendar!, DisplayName = p.Calendar! };
        var doc = await DavXml.ReadBodyAsync(ctx.Request);
        var props = doc?.Root?.Elements(Ns.Dav + "set").Elements(Ns.Dav + "prop").Elements() ?? [];
        foreach (var prop in props)
        {
            var value = prop.Value.Trim();
            if (prop.Name == Ns.Dav + "displayname" && value.Length is > 0 and <= 256) cal.DisplayName = value;
            else if (prop.Name == Ns.CalDav + "calendar-description") cal.Description = value;
            else if (prop.Name == Ns.Apple + "calendar-color" && ColorRegex().IsMatch(value)) cal.Color = value;
        }
        db.Calendars.Add(cal);
        await db.SaveChangesAsync();
        ctx.Response.StatusCode = StatusCodes.Status201Created;
    }

    // -------------------------------------------------------------------------
    // REPORT
    // -------------------------------------------------------------------------

    private async Task ReportAsync(HttpContext ctx, DavPath p)
    {
        var res = await ResolveAsync(p);
        if (res is null)
        {
            ctx.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }
        var doc = await DavXml.ReadBodyAsync(ctx.Request);
        var root = doc?.Root ?? throw new BadRequestException("Missing REPORT body");
        var (mode, names) = ParsePropRequest(root);

        if (root.Name == Ns.CalDav + "calendar-query" && res.Calendar is not null)
        {
            var compFilter = root.Element(Ns.CalDav + "filter")?.Element(Ns.CalDav + "comp-filter")
                ?.Element(Ns.CalDav + "comp-filter");
            var component = compFilter?.Attribute("name")?.Value.ToUpperInvariant();
            var range = compFilter?.Element(Ns.CalDav + "time-range");
            long? start = ParseRangeBound(range?.Attribute("start")?.Value);
            long? end = ParseRangeBound(range?.Attribute("end")?.Value);

            var query = db.CalendarObjects.Where(o => o.CalendarId == res.Calendar.Id);
            if (res.Object is not null) query = query.Where(o => o.Id == res.Object.Id);
            if (component is not null) query = query.Where(o => o.ComponentType == component);
            if (end is not null) query = query.Where(o => o.FirstStartMs == null || o.FirstStartMs < end);
            if (start is not null) query = query.Where(o => o.LastEndMs == null || o.LastEndMs > start);
            var objects = await query.OrderBy(o => o.Id).ToListAsync();

            await DavXml.WriteAsync(ctx.Response, 207, DavXml.Multistatus(objects.Select(o =>
                BuildResponse(new Res(ObjectHref(res.Calendar, o), DavResourceKind.Object, res.Calendar, o), mode, names))));
            return;
        }

        if (root.Name == Ns.CalDav + "calendar-multiget")
        {
            var responses = new List<XElement>();
            foreach (var hrefEl in root.Elements(Ns.Dav + "href"))
            {
                var target = DavPath.ParseHref(hrefEl.Value, _base);
                Res? r = null;
                if (target is { Kind: DavResourceKind.Object } && target.User == _user.Username)
                    r = await ResolveAsync(target);
                responses.Add(r is null
                    ? DavXml.StatusResponse(hrefEl.Value.Trim(), 404)
                    : BuildResponse(r, mode, names));
            }
            await DavXml.WriteAsync(ctx.Response, 207, DavXml.Multistatus(responses));
            return;
        }

        await DavXml.WriteAsync(ctx.Response, 403, DavXml.Error(Ns.Dav + "supported-report"));
    }

    private static long? ParseRangeBound(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var d = IcsInspector.ParseDate(value, out _) ?? throw new BadRequestException($"Invalid time-range value '{value}'");
        return new DateTimeOffset(d).ToUnixTimeMilliseconds();
    }

    // -------------------------------------------------------------------------
    // GET / HEAD
    // -------------------------------------------------------------------------

    private async Task GetAsync(HttpContext ctx, DavPath p, bool includeBody)
    {
        var res = await ResolveAsync(p);
        if (res is null)
        {
            ctx.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }
        string body, etag;
        switch (res.Kind)
        {
            case DavResourceKind.Object:
                body = res.Object!.Data;
                etag = res.Object.ETag;
                ctx.Response.Headers.LastModified = res.Object.LastModified.ToString("R");
                break;
            case DavResourceKind.Calendar:
                // Whole calendar as a single .ics file (export / subscription).
                var data = await db.CalendarObjects.Where(o => o.CalendarId == res.Calendar!.Id)
                    .OrderBy(o => o.Id).Select(o => o.Data).ToListAsync();
                body = IcsInspector.Merge(data, res.Calendar!.DisplayName);
                etag = $"\"{CTagValue(res.Calendar)}\"";
                break;
            default:
                ctx.Response.Headers.Allow = AllowHeader;
                ctx.Response.StatusCode = StatusCodes.Status405MethodNotAllowed;
                return;
        }
        ctx.Response.StatusCode = StatusCodes.Status200OK;
        ctx.Response.ContentType = "text/calendar; charset=utf-8";
        ctx.Response.Headers.ETag = etag;
        var bytes = Encoding.UTF8.GetBytes(body);
        ctx.Response.ContentLength = bytes.Length;
        if (includeBody) await ctx.Response.Body.WriteAsync(bytes);
    }

    // -------------------------------------------------------------------------
    // PUT
    // -------------------------------------------------------------------------

    private async Task PutAsync(HttpContext ctx, DavPath p)
    {
        if (p.Kind != DavResourceKind.Object || p.Object!.Length > 255)
        {
            ctx.Response.StatusCode = StatusCodes.Status405MethodNotAllowed;
            return;
        }
        var cal = await FindCalendarAsync(p.Calendar!);
        if (cal is null)
        {
            ctx.Response.StatusCode = StatusCodes.Status409Conflict;
            return;
        }

        var contentType = ctx.Request.ContentType;
        if (contentType is not null && !contentType.Contains("text/calendar", StringComparison.OrdinalIgnoreCase))
        {
            await DavXml.WriteAsync(ctx.Response, 415, DavXml.Error(Ns.CalDav + "supported-calendar-data"));
            return;
        }

        using var buffer = new MemoryStream();
        await ctx.Request.Body.CopyToAsync(buffer);
        if (buffer.Length > MaxResourceSize)
        {
            await DavXml.WriteAsync(ctx.Response, 403, DavXml.Error(Ns.CalDav + "max-resource-size"));
            return;
        }
        var data = Encoding.UTF8.GetString(buffer.ToArray());

        IcsSummary summary;
        try
        {
            summary = IcsInspector.Inspect(data);
        }
        catch (InvalidCalendarDataException e)
        {
            logger.LogInformation("Rejected invalid calendar data: {Message}", e.Message);
            await DavXml.WriteAsync(ctx.Response, 403, DavXml.Error(Ns.CalDav + "valid-calendar-data"));
            return;
        }

        var existing = await FindObjectAsync(cal, p.Object!);

        // Preconditions (RFC 7232).
        var ifNoneMatch = ctx.Request.Headers.IfNoneMatch.ToString();
        var ifMatch = ctx.Request.Headers.IfMatch.ToString();
        if ((ifNoneMatch.Trim() == "*" && existing is not null) ||
            (ifMatch.Length > 0 && (existing is null || !EtagMatches(ifMatch, existing.ETag))))
        {
            ctx.Response.StatusCode = StatusCodes.Status412PreconditionFailed;
            return;
        }

        var conflict = await db.CalendarObjects
            .Where(o => o.CalendarId == cal.Id && o.Uid == summary.Uid && o.Name != p.Object)
            .Select(o => o.Name).FirstOrDefaultAsync();
        if (conflict is not null)
        {
            await DavXml.WriteAsync(ctx.Response, 403, DavXml.Error(Ns.CalDav + "no-uid-conflict",
                DavPath.ObjectHref(_base, _user.Username, cal.Slug, conflict)));
            return;
        }

        var etag = "\"" + Convert.ToHexString(SHA256.HashData(buffer.ToArray()))[..32].ToLowerInvariant() + "\"";
        var created = existing is null;
        var obj = existing ?? new CalendarObject
        {
            CalendarId = cal.Id, Name = p.Object!, Uid = summary.Uid, ComponentType = summary.ComponentType,
            Data = data, ETag = etag,
        };
        obj.Uid = summary.Uid;
        obj.ComponentType = summary.ComponentType;
        obj.Data = data;
        obj.ETag = etag;
        obj.FirstStartMs = summary.FirstStartMs;
        obj.LastEndMs = summary.LastEndMs;
        obj.LastModified = DateTime.UtcNow;
        if (created) db.CalendarObjects.Add(obj);

        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            // Concurrent creation of the same name or UID.
            ctx.Response.StatusCode = StatusCodes.Status409Conflict;
            return;
        }
        await BumpCTagAsync(cal);

        ctx.Response.Headers.ETag = etag;
        ctx.Response.StatusCode = created ? StatusCodes.Status201Created : StatusCodes.Status204NoContent;
    }

    private static bool EtagMatches(string header, string etag) =>
        header.Split(',').Select(v => v.Trim()).Any(v => v == "*" || v == etag || v == "W/" + etag);

    private Task BumpCTagAsync(Calendar cal) =>
        db.Calendars.Where(c => c.Id == cal.Id).ExecuteUpdateAsync(s => s.SetProperty(c => c.CTag, c => c.CTag + 1));

    // -------------------------------------------------------------------------
    // DELETE
    // -------------------------------------------------------------------------

    private async Task DeleteAsync(HttpContext ctx, DavPath p)
    {
        var res = await ResolveAsync(p);
        if (res is null)
        {
            ctx.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }
        var ifMatch = ctx.Request.Headers.IfMatch.ToString();
        switch (res.Kind)
        {
            case DavResourceKind.Object:
                if (ifMatch.Length > 0 && !EtagMatches(ifMatch, res.Object!.ETag))
                {
                    ctx.Response.StatusCode = StatusCodes.Status412PreconditionFailed;
                    return;
                }
                db.CalendarObjects.Remove(res.Object!);
                await db.SaveChangesAsync();
                await BumpCTagAsync(res.Calendar!);
                break;
            case DavResourceKind.Calendar:
                db.Calendars.Remove(res.Calendar!);
                await db.SaveChangesAsync();
                break;
            default:
                ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
                return;
        }
        ctx.Response.StatusCode = StatusCodes.Status204NoContent;
    }
}
