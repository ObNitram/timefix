using TimeFix.Server.CalDav;

namespace TimeFix.Server.Tests;

public class IcsInspectorTests
{
    private static long Ms(int y, int m, int d, int h = 0) =>
        new DateTimeOffset(y, m, d, h, 0, 0, TimeSpan.Zero).ToUnixTimeMilliseconds();

    [Fact]
    public void Utc_event_bounds_include_slack()
    {
        var s = IcsInspector.Inspect(Dav.Event("u", "20261110T090000Z", "20261110T100000Z"));
        Assert.Equal("u", s.Uid);
        Assert.Equal("VEVENT", s.ComponentType);
        Assert.Equal(Ms(2026, 11, 9, 19), s.FirstStartMs);
        Assert.Equal(Ms(2026, 11, 11, 0), s.LastEndMs);
    }

    [Fact]
    public void All_day_event_defaults_to_one_day()
    {
        var s = IcsInspector.Inspect(
            "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:d\r\nDTSTART;VALUE=DATE:20261111\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
        Assert.Equal(Ms(2026, 11, 12, 14), s.LastEndMs);
    }

    [Fact]
    public void Infinite_recurrence_is_unbounded_and_overrides_are_accepted()
    {
        var ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:r\r\nDTSTART:20260105T090000Z\r\nDTEND:20260105T100000Z\r\n" +
                  "RRULE:FREQ=WEEKLY\r\nBEGIN:VALARM\r\nTRIGGER:-PT10M\r\nUID:alarm-uid\r\nEND:VALARM\r\nEND:VEVENT\r\n" +
                  "BEGIN:VEVENT\r\nUID:r\r\nRECURRENCE-ID:20260112T090000Z\r\nDTSTART:20260112T110000Z\r\n" +
                  "DTEND:20260112T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
        var s = IcsInspector.Inspect(ics);
        Assert.Equal("r", s.Uid);
        Assert.Null(s.LastEndMs);
    }

    [Fact]
    public void Undated_todo_matches_any_range()
    {
        var s = IcsInspector.Inspect("BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:t\r\nSUMMARY:x\r\nEND:VTODO\r\nEND:VCALENDAR\r\n");
        Assert.Equal("VTODO", s.ComponentType);
        Assert.Null(s.FirstStartMs);
        Assert.Null(s.LastEndMs);
    }

    [Theory]
    [InlineData("BEGIN:VEVENT\r\nUID:x\r\nEND:VEVENT\r\n")]
    [InlineData("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n")]
    [InlineData("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:b\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")]
    [InlineData("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nEND:VEVENT\r\nBEGIN:VTODO\r\nUID:a\r\nEND:VTODO\r\nEND:VCALENDAR\r\n")]
    [InlineData("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nEND:VCALENDAR\r\n")]
    [InlineData("BEGIN:VCALENDAR\r\nBEGIN:VFREEBUSY\r\nUID:a\r\nEND:VFREEBUSY\r\nEND:VCALENDAR\r\n")]
    public void Invalid_resources_are_rejected(string ics) =>
        Assert.Throws<InvalidCalendarDataException>(() => IcsInspector.Inspect(ics));

    [Fact]
    public void Folded_lines_are_unfolded()
    {
        var s = IcsInspector.Inspect(
            "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:very-long-\r\n uid\r\nDTSTART:20261110T090000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
        Assert.Equal("very-long-uid", s.Uid);
    }
}
