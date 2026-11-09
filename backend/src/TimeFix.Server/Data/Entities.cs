namespace TimeFix.Server.Data;

public class User
{
    public int Id { get; set; }

    /// <summary>Lower-case login, also used in CalDAV URLs.</summary>
    public required string Username { get; set; }

    public required string PasswordHash { get; set; }
    public bool IsAdmin { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<Calendar> Calendars { get; set; } = [];
}

/// <summary>A CalDAV calendar collection: /dav/calendars/{user}/{slug}/</summary>
public class Calendar
{
    public int Id { get; set; }
    public int OwnerId { get; set; }
    public User? Owner { get; set; }

    /// <summary>Last URL segment of the collection.</summary>
    public required string Slug { get; set; }

    public required string DisplayName { get; set; }
    public string? Description { get; set; }

    /// <summary>Color as "#RRGGBB" or "#RRGGBBAA" (Apple calendar-color).</summary>
    public string? Color { get; set; }

    /// <summary>Incremented on every change, exposed as the CalendarServer "getctag".</summary>
    public long CTag { get; set; } = 1;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<CalendarObject> Objects { get; set; } = [];
}

/// <summary>A calendar object resource (one .ics file).</summary>
public class CalendarObject
{
    public int Id { get; set; }
    public int CalendarId { get; set; }
    public Calendar? Calendar { get; set; }

    /// <summary>Resource name, e.g. "3f2a….ics".</summary>
    public required string Name { get; set; }

    /// <summary>iCalendar UID, unique inside a calendar (RFC 4791 §4.1).</summary>
    public required string Uid { get; set; }

    /// <summary>VEVENT, VTODO or VJOURNAL.</summary>
    public required string ComponentType { get; set; }

    public required string Data { get; set; }
    public required string ETag { get; set; }

    /// <summary>
    /// Conservative bounds of all occurrences, in Unix milliseconds (UTC),
    /// used for calendar-query time-range filters. Null means unbounded.
    /// </summary>
    public long? FirstStartMs { get; set; }
    public long? LastEndMs { get; set; }

    public DateTime LastModified { get; set; } = DateTime.UtcNow;
}
