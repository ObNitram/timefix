namespace TimeFix.Server.CalDav;

public enum DavResourceKind
{
    Root,          // /dav/
    Principals,    // /dav/principals/
    Principal,     // /dav/principals/{user}/
    Calendars,     // /dav/calendars/
    CalendarHome,  // /dav/calendars/{user}/
    Calendar,      // /dav/calendars/{user}/{calendar}/
    Object,        // /dav/calendars/{user}/{calendar}/{object}
    Unknown,
}

/// <summary>Parsed location inside the /dav namespace.</summary>
public sealed record DavPath(DavResourceKind Kind, string? User = null, string? Calendar = null, string? Object = null)
{
    public const string Prefix = "/dav";

    /// <summary>Parses the decoded path relative to <see cref="Prefix"/>.</summary>
    public static DavPath Parse(string? relative)
    {
        var segments = (relative ?? "").Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Any(s => s is "." or "..")) return new(DavResourceKind.Unknown);
        return segments switch
        {
            [] => new(DavResourceKind.Root),
            ["principals"] => new(DavResourceKind.Principals),
            ["principals", var u] => new(DavResourceKind.Principal, u),
            ["calendars"] => new(DavResourceKind.Calendars),
            ["calendars", var u] => new(DavResourceKind.CalendarHome, u),
            ["calendars", var u, var c] => new(DavResourceKind.Calendar, u, c),
            ["calendars", var u, var c, var o] => new(DavResourceKind.Object, u, c, o),
            _ => new(DavResourceKind.Unknown),
        };
    }

    /// <summary>Parses an href received in a request body (absolute URL or absolute path).</summary>
    public static DavPath? ParseHref(string href, string pathBase)
    {
        var path = href.Trim();
        if (Uri.TryCreate(path, UriKind.Absolute, out var abs) && abs.Scheme.StartsWith("http"))
        {
            path = abs.AbsolutePath;
        }
        path = Uri.UnescapeDataString(path);
        var prefix = pathBase + Prefix;
        if (!path.StartsWith(prefix, StringComparison.Ordinal)) return null;
        return Parse(path[prefix.Length..]);
    }

    public static string Href(string pathBase, params string[] segments)
    {
        var path = pathBase + Prefix + "/" + string.Join('/', segments.Select(Uri.EscapeDataString));
        return path;
    }

    public static string PrincipalHref(string pathBase, string user) => Href(pathBase, "principals", user) + "/";
    public static string HomeHref(string pathBase, string user) => Href(pathBase, "calendars", user) + "/";
    public static string CalendarHref(string pathBase, string user, string calendar) =>
        Href(pathBase, "calendars", user, calendar) + "/";
    public static string ObjectHref(string pathBase, string user, string calendar, string obj) =>
        Href(pathBase, "calendars", user, calendar, obj);
}
