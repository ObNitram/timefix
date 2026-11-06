using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using TimeFix.Server.Users;

namespace TimeFix.Server.Auth;

/// <summary>
/// HTTP Basic authentication (the scheme every CalDAV client supports).
/// Must be served over HTTPS, typically behind a reverse proxy.
///
/// Successful verifications are cached for a few minutes because password
/// hashing is deliberately slow and CalDAV clients authenticate every request.
/// Clients with too many failures are temporarily rejected.
/// </summary>
public class BasicAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    UserService users,
    IMemoryCache cache)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "Basic";
    public const string AdminClaim = "timefix:admin";
    public const int MaxFailures = 10;
    private static readonly TimeSpan FailureWindow = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan SuccessCache = TimeSpan.FromMinutes(5);

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("Authorization", out var header)) return AuthenticateResult.NoResult();
        if (!AuthenticationHeaderValue.TryParse(header, out var value) ||
            !string.Equals(value.Scheme, SchemeName, StringComparison.OrdinalIgnoreCase) ||
            value.Parameter is null)
        {
            return AuthenticateResult.NoResult();
        }

        var ip = Context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        var failureKey = $"auth-failures:{ip}";
        if (cache.TryGetValue(failureKey, out int failures) && failures >= MaxFailures)
        {
            return AuthenticateResult.Fail("Too many failed attempts");
        }

        string username, password;
        try
        {
            var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(value.Parameter));
            var colon = decoded.IndexOf(':');
            if (colon <= 0) return AuthenticateResult.Fail("Invalid credentials");
            username = UserService.NormalizeUsername(decoded[..colon]);
            password = decoded[(colon + 1)..];
        }
        catch (FormatException)
        {
            return AuthenticateResult.Fail("Invalid credentials");
        }

        var user = await users.FindAsync(username);
        var ok = false;
        if (user is not null)
        {
            // The key changes when the stored hash changes, so password resets
            // invalidate the cache automatically.
            var key = "auth-ok:" + Convert.ToHexString(SHA256.HashData(
                Encoding.UTF8.GetBytes($"{user.Id}\n{user.PasswordHash}\n{password}")));
            if (cache.TryGetValue(key, out _))
            {
                ok = true;
            }
            else if (users.VerifyPassword(user, password))
            {
                ok = true;
                cache.Set(key, true, SuccessCache);
            }
        }

        if (!ok || user is null)
        {
            cache.Set(failureKey, failures + 1, FailureWindow);
            return AuthenticateResult.Fail("Invalid credentials");
        }

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.Username),
        };
        if (user.IsAdmin) claims.Add(new Claim(AdminClaim, "true"));
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, SchemeName));
        return AuthenticateResult.Success(new AuthenticationTicket(principal, SchemeName));
    }

    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        Response.StatusCode = StatusCodes.Status401Unauthorized;
        Response.Headers.WWWAuthenticate = "Basic realm=\"TimeFix\", charset=\"UTF-8\"";
        return Task.CompletedTask;
    }
}

public static class ClaimsPrincipalExtensions
{
    public static int UserId(this ClaimsPrincipal p) =>
        int.Parse(p.FindFirstValue(ClaimTypes.NameIdentifier)!);

    public static string Username(this ClaimsPrincipal p) => p.FindFirstValue(ClaimTypes.Name)!;
}
