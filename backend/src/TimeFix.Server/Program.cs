using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using TimeFix.Server.Api;
using TimeFix.Server.Auth;
using TimeFix.Server.CalDav;
using TimeFix.Server.Data;
using TimeFix.Server.Users;

// `dotnet TimeFix.Server.dll healthcheck` is used by the Docker HEALTHCHECK
// (the runtime image has no curl).
if (args.Length > 0 && args[0] == "healthcheck")
{
    var port = Environment.GetEnvironmentVariable("ASPNETCORE_HTTP_PORTS")?.Split(';')[0] ?? "8080";
    try
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        var response = await client.GetAsync($"http://127.0.0.1:{port}/health");
        return response.IsSuccessStatusCode ? 0 : 1;
    }
    catch
    {
        return 1;
    }
}

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

builder.Services.AddTimeFixDatabase(config);
builder.Services.AddMemoryCache();
builder.Services.AddScoped<IPasswordHasher<User>, PasswordHasher<User>>();
builder.Services.AddScoped<UserService>();
builder.Services.AddScoped<CalDavHandler>();

builder.Services.AddAuthentication(BasicAuthenticationHandler.SchemeName)
    .AddScheme<AuthenticationSchemeOptions, BasicAuthenticationHandler>(BasicAuthenticationHandler.SchemeName, null);
builder.Services.AddAuthorizationBuilder()
    .AddPolicy(AccountEndpoints.AdminPolicy, p => p.RequireClaim(BasicAuthenticationHandler.AdminClaim, "true"));

// Per-client request limit (protects against brute force and abuse).
var permitsPerMinute = config.GetValue("RateLimit:PermitsPerMinute", 600);
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx =>
        RateLimitPartition.GetFixedWindowLimiter(
            ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = permitsPerMinute, Window = TimeSpan.FromMinutes(1) }));
});

// Behind a TLS reverse proxy (Caddy, Traefik, nginx…), set ReverseProxy:Enabled
// so that the client IP used for rate limiting and lock-out comes from
// X-Forwarded-For. Leave it off when the port is reachable directly, otherwise
// clients could spoof their address.
var behindProxy = config.GetValue("ReverseProxy:Enabled", false);
builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    o.ForwardLimit = 1;
    o.KnownIPNetworks.Clear();
    o.KnownProxies.Clear();
});

builder.WebHost.ConfigureKestrel(k => k.Limits.MaxRequestBodySize = 10 * 1024 * 1024);

var app = builder.Build();

await DatabaseSetup.MigrateAsync(app.Services, app.Logger);
using (var scope = app.Services.CreateScope())
{
    await scope.ServiceProvider.GetRequiredService<UserService>().BootstrapAdminAsync(app.Logger);
}

if (behindProxy) app.UseForwardedHeaders();
if (config["PathBase"] is { Length: > 0 } pathBase) app.UsePathBase(pathBase);
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health", () => Results.Text("ok"));
app.MapGet("/", () => Results.Text("TimeFix CalDAV server. CalDAV endpoint: /dav/"));

// RFC 6764 service discovery.
app.MapMethods("/.well-known/caldav", ["GET", "HEAD", "PROPFIND", "OPTIONS"], (HttpContext ctx) =>
    Results.Redirect((ctx.Request.PathBase.Value ?? "") + "/dav/", permanent: true));

app.MapMethods("/dav/{**path}", ["OPTIONS"], CalDavHandler.Options);
app.MapMethods("/dav/{**path}", CalDavHandler.Methods,
        (HttpContext ctx, string? path, CalDavHandler handler) => handler.HandleAsync(ctx, path))
    .RequireAuthorization();

app.MapAccountEndpoints();

app.Run();
return 0;

public partial class Program;
