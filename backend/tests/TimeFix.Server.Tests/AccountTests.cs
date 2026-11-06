using System.Net;
using System.Net.Http.Json;
using TimeFix.Server.Api;

namespace TimeFix.Server.Tests;

public class AccountTests : IDisposable
{
    private readonly TimeFixFactory _factory = new();
    private readonly HttpClient _admin;

    public AccountTests() => _admin = _factory.AdminClient();

    public void Dispose() => _factory.Dispose();

    [Fact]
    public async Task Admin_manages_users()
    {
        var create = await _admin.PostAsJsonAsync("/api/admin/users",
            new { username = "Alice", password = "alice-password" });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var dto = await create.Content.ReadFromJsonAsync<UserDto>();
        Assert.Equal("alice", dto!.Username);
        Assert.Equal(1, dto.CalendarCount);

        var duplicate = await _admin.PostAsJsonAsync("/api/admin/users", new { username = "alice", password = "another-pw" });
        Assert.Equal(HttpStatusCode.BadRequest, duplicate.StatusCode);
        var invalidName = await _admin.PostAsJsonAsync("/api/admin/users", new { username = "a/b", password = "password1" });
        Assert.Equal(HttpStatusCode.BadRequest, invalidName.StatusCode);
        var shortPassword = await _admin.PostAsJsonAsync("/api/admin/users", new { username = "carol", password = "short" });
        Assert.Equal(HttpStatusCode.BadRequest, shortPassword.StatusCode);

        var list = await _admin.GetFromJsonAsync<List<UserDto>>("/api/admin/users");
        Assert.Equal(["admin", "alice"], list!.Select(u => u.Username));

        var reset = await _admin.PutAsJsonAsync("/api/admin/users/alice/password", new { password = "new-alice-pw" });
        Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await _factory.ClientFor("alice", "alice-password").GetAsync("/api/me")).StatusCode);
        var alice = _factory.ClientFor("alice", "new-alice-pw");
        var me = await alice.GetFromJsonAsync<MeDto>("/api/me");
        Assert.Equal("/dav/calendars/alice/", me!.CalendarHomeUrl);
        Assert.False(me.IsAdmin);

        Assert.Equal(HttpStatusCode.Forbidden, (await alice.GetAsync("/api/admin/users")).StatusCode);

        Assert.Equal(HttpStatusCode.NoContent, (await _admin.DeleteAsync("/api/admin/users/alice")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await _admin.DeleteAsync("/api/admin/users/admin")).StatusCode);
    }

    [Fact]
    public async Task Users_change_their_own_password()
    {
        var wrong = await _admin.PutAsJsonAsync("/api/me/password",
            new { currentPassword = "wrong", newPassword = "brand-new-password" });
        Assert.Equal(HttpStatusCode.Forbidden, wrong.StatusCode);
        var ok = await _admin.PutAsJsonAsync("/api/me/password",
            new { currentPassword = TimeFixFactory.AdminPassword, newPassword = "brand-new-password" });
        Assert.Equal(HttpStatusCode.NoContent, ok.StatusCode);
        Assert.Equal(HttpStatusCode.OK,
            (await _factory.ClientFor("admin", "brand-new-password").GetAsync("/api/me")).StatusCode);
    }
}

public class BruteForceTests : IDisposable
{
    private readonly TimeFixFactory _factory = new();

    public void Dispose() => _factory.Dispose();

    [Fact]
    public async Task Repeated_failures_lock_the_client_out()
    {
        var wrong = _factory.ClientFor("admin", "guess");
        for (var i = 0; i < 10; i++)
        {
            Assert.Equal(HttpStatusCode.Unauthorized, (await wrong.GetAsync("/api/me")).StatusCode);
        }
        // Even the right password is refused while locked out.
        Assert.Equal(HttpStatusCode.Unauthorized, (await _factory.AdminClient().GetAsync("/api/me")).StatusCode);

        // A spoofed X-Forwarded-For does not escape the lock-out (no reverse proxy configured).
        var spoofed = _factory.AdminClient();
        spoofed.DefaultRequestHeaders.Add("X-Forwarded-For", "203.0.113.7");
        Assert.Equal(HttpStatusCode.Unauthorized, (await spoofed.GetAsync("/api/me")).StatusCode);
    }
}
