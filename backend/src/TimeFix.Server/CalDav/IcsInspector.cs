using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace TimeFix.Server.CalDav;

public class InvalidCalendarDataException(string message) : Exception(message);

/// <summary>Information extracted from a calendar object resource.</summary>
public sealed record IcsSummary(string Uid, string ComponentType, long? FirstStartMs, long? LastEndMs);

/// <summary>
/// Minimal iCalendar (RFC 5545) inspection: validates a calendar object
/// resource (RFC 4791 §4.1) and computes conservative time bounds.
///
/// Bounds are a superset of the real occurrence range: floating times and
/// times with a TZID are widened by 14 hours (the largest UTC offset), and
/// open-ended recurrences are unbounded. This keeps time-range filtering
/// correct without a full time zone / recurrence engine on the server.
/// </summary>
public static partial class IcsInspector
{
    private static readonly TimeSpan Slack = TimeSpan.FromHours(14);
    private static readonly string[] SupportedComponents = ["VEVENT", "VTODO", "VJOURNAL"];

    public static IReadOnlyList<string> Unfold(string data)
    {
        var lines = new List<string>();
        foreach (var raw in data.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
        {
            if ((raw.StartsWith(' ') || raw.StartsWith('\t')) && lines.Count > 0)
            {
                lines[^1] += raw[1..];
            }
            else
            {
                lines.Add(raw);
            }
        }
        return lines;
    }

    public static IcsSummary Inspect(string data)
    {
        var lines = Unfold(data);
        var stack = new Stack<string>();
        var components = new List<Dictionary<string, (string Params, string Value)>>();
        string? componentType = null;
        Dictionary<string, (string, string)>? current = null;
        var sawCalendar = false;

        foreach (var line in lines)
        {
            if (line.Length == 0) continue;
            var (name, parameters, value) = ParseLine(line);
            if (name == "BEGIN")
            {
                var comp = value.Trim().ToUpperInvariant();
                if (stack.Count == 0)
                {
                    if (comp != "VCALENDAR") throw new InvalidCalendarDataException("Expected BEGIN:VCALENDAR");
                    sawCalendar = true;
                }
                else if (stack.Count == 1 && comp != "VTIMEZONE")
                {
                    if (!SupportedComponents.Contains(comp))
                        throw new InvalidCalendarDataException($"Unsupported component {comp}");
                    if (componentType is not null && componentType != comp)
                        throw new InvalidCalendarDataException("A resource must contain a single component type");
                    componentType = comp;
                    current = new Dictionary<string, (string, string)>();
                    components.Add(current);
                }
                stack.Push(comp);
                continue;
            }
            if (name == "END")
            {
                var comp = value.Trim().ToUpperInvariant();
                if (stack.Count == 0 || stack.Peek() != comp)
                    throw new InvalidCalendarDataException($"Unbalanced END:{comp}");
                stack.Pop();
                if (stack.Count == 1) current = null;
                continue;
            }
            // Only properties directly inside the component (not VALARM etc.).
            if (current is not null && stack.Count == 2 && !current.ContainsKey(name))
            {
                current[name] = (parameters, value);
            }
        }

        if (!sawCalendar || stack.Count != 0) throw new InvalidCalendarDataException("Malformed VCALENDAR");
        if (componentType is null || components.Count == 0)
            throw new InvalidCalendarDataException("No VEVENT, VTODO or VJOURNAL component");

        var uids = components.Select(c => c.TryGetValue("UID", out var u) ? u.Value.Trim() : "").Distinct().ToList();
        if (uids.Count != 1 || uids[0].Length == 0)
            throw new InvalidCalendarDataException("All components must share one non-empty UID");

        long? first = long.MaxValue, last = long.MinValue;
        foreach (var c in components)
        {
            var (start, end) = ComponentBounds(c);
            first = first is null || start is null ? null : Math.Min(first.Value, start.Value);
            last = last is null || end is null ? null : Math.Max(last.Value, end.Value);
        }
        return new IcsSummary(uids[0], componentType, first, last);
    }

    private static (long? Start, long? End) ComponentBounds(Dictionary<string, (string Params, string Value)> c)
    {
        DateTime? start = c.TryGetValue("DTSTART", out var s) ? ParseDate(s.Value, out _) : null;
        bool startIsDate = s.Value is not null && IsDateValue(s.Value);
        DateTime? end = null;
        if (c.TryGetValue("DTEND", out var e) || c.TryGetValue("DUE", out e)) end = ParseDate(e.Value, out _);
        else if (start is not null && c.TryGetValue("DURATION", out var d) && ParseDuration(d.Value) is { } dur)
            end = start + dur;

        if (start is null && end is null) return (null, null); // e.g. undated VTODO: matches any range
        start ??= end;
        end ??= startIsDate ? start!.Value.AddDays(1) : start;
        if (end < start) end = start;

        DateTime? lastEnd = end;
        if (c.ContainsKey("RDATE")) lastEnd = null;
        if (c.TryGetValue("RRULE", out var rrule))
        {
            var until = Regex.Match(rrule.Value, @"UNTIL=([0-9TZ]+)", RegexOptions.IgnoreCase);
            lastEnd = until.Success && ParseDate(until.Groups[1].Value, out _) is { } u
                ? u.AddDays(1) + (end!.Value - start!.Value)
                : null; // COUNT or infinite: unbounded (conservative)
        }

        return (ToMs(start!.Value - Slack), lastEnd is null ? null : ToMs(lastEnd.Value + Slack));
    }

    private static long ToMs(DateTime d) => new DateTimeOffset(DateTime.SpecifyKind(d, DateTimeKind.Utc)).ToUnixTimeMilliseconds();

    private static bool IsDateValue(string v) => Regex.IsMatch(v.Trim(), @"^\d{8}$");

    /// <summary>Parses DATE or DATE-TIME values; non-UTC values are read as UTC (callers add slack).</summary>
    public static DateTime? ParseDate(string value, out bool isUtc)
    {
        var v = value.Trim();
        isUtc = v.EndsWith('Z');
        string[] formats = ["yyyyMMdd'T'HHmmss'Z'", "yyyyMMdd'T'HHmmss", "yyyyMMdd'T'HHmm", "yyyyMMdd"];
        return DateTime.TryParseExact(v, formats, CultureInfo.InvariantCulture,
            DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var d)
            ? DateTime.SpecifyKind(d, DateTimeKind.Utc)
            : null;
    }

    public static TimeSpan? ParseDuration(string value)
    {
        var m = Regex.Match(value.Trim(),
            @"^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$");
        if (!m.Success) return null;
        int G(int i) => m.Groups[i].Success ? int.Parse(m.Groups[i].Value, CultureInfo.InvariantCulture) : 0;
        var d = new TimeSpan(G(2) * 7 + G(3), G(4), G(5), G(6));
        return m.Groups[1].Value == "-" ? -d : d;
    }

    /// <summary>Splits "NAME;PARAM=x:value" (colons inside quoted parameters are ignored).</summary>
    public static (string Name, string Params, string Value) ParseLine(string line)
    {
        var inQuotes = false;
        for (var i = 0; i < line.Length; i++)
        {
            var ch = line[i];
            if (ch == '"') inQuotes = !inQuotes;
            else if (ch == ':' && !inQuotes)
            {
                var head = line[..i];
                var semi = head.IndexOf(';');
                var name = (semi < 0 ? head : head[..semi]).Trim().ToUpperInvariant();
                return (name, semi < 0 ? "" : head[(semi + 1)..], line[(i + 1)..]);
            }
        }
        return (line.Trim().ToUpperInvariant(), "", "");
    }

    /// <summary>
    /// Merges several resources into one VCALENDAR (calendar export), keeping
    /// each VTIMEZONE once.
    /// </summary>
    public static string Merge(IEnumerable<string> resources, string calendarName)
    {
        var sb = new StringBuilder();
        sb.Append("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//TimeFix//Server//EN\r\n");
        sb.Append("X-WR-CALNAME:").Append(EscapeText(calendarName)).Append("\r\n");
        var timezones = new HashSet<string>();
        var body = new StringBuilder();
        foreach (var data in resources)
        {
            var lines = Unfold(data);
            var depth = 0;
            StringBuilder? block = null;
            string? tzid = null;
            foreach (var line in lines)
            {
                if (line.Length == 0) continue;
                var (name, _, value) = ParseLine(line);
                if (name == "BEGIN") depth++;
                if (depth >= 2)
                {
                    block ??= new StringBuilder();
                    block.Append(line).Append("\r\n");
                    if (depth == 2 && name == "TZID") tzid = value.Trim();
                }
                if (name == "END")
                {
                    depth--;
                    if (depth == 1 && block is not null)
                    {
                        var text = block.ToString();
                        if (text.StartsWith("BEGIN:VTIMEZONE", StringComparison.OrdinalIgnoreCase))
                        {
                            if (tzid is null || timezones.Add(tzid)) sb.Append(text);
                        }
                        else
                        {
                            body.Append(text);
                        }
                        block = null;
                        tzid = null;
                    }
                }
            }
        }
        sb.Append(body).Append("END:VCALENDAR\r\n");
        return sb.ToString();
    }

    public static string EscapeText(string s) =>
        s.Replace("\\", "\\\\").Replace(";", "\\;").Replace(",", "\\,").Replace("\n", "\\n");
}
