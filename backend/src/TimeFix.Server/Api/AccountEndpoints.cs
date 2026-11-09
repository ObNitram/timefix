using Microsoft.EntityFrameworkCore;
using TimeFix.Server.Auth;
using TimeFix.Server.CalDav;
using TimeFix.Server.Data;
using TimeFix.Server.Users;

namespace TimeFix.Server.Api;

public record UserDto(string Username, bool IsAdmin, DateTime CreatedAt, int CalendarCount);
public record CreateUserRequest(string Username, string Password, bool IsAdmin = false);
public record SetPasswordRequest(string Password);
public record ChangeOwnPasswordRequest(string CurrentPassword, string NewPassword);
public record MeDto(string Username, bool IsAdmin, string PrincipalUrl, string CalendarHomeUrl);

public static class AccountEndpoints
{
    public const string AdminPolicy = "admin";

    public static void MapAccountEndpoints(this IEndpointRouteBuilder app)
    {
        var me = app.MapGroup("/api/me").RequireAuthorization();

        me.MapGet("", (HttpContext ctx) =>
        {
            var name = ctx.User.Username();
            var basePath = ctx.Request.PathBase.Value ?? "";
            return new MeDto(name, ctx.User.HasClaim(BasicAuthenticationHandler.AdminClaim, "true"),
                DavPath.PrincipalHref(basePath, name), DavPath.HomeHref(basePath, name));
        });

        me.MapPut("/password", async (ChangeOwnPasswordRequest body, HttpContext ctx, UserService users) =>
        {
            var user = await users.FindAsync(ctx.User.Username());
            if (user is null || !users.VerifyPassword(user, body.CurrentPassword)) return Results.Forbid();
            return await Validated(() => users.SetPasswordAsync(user, body.NewPassword), Results.NoContent());
        });

        var admin = app.MapGroup("/api/admin/users").RequireAuthorization(AdminPolicy);

        admin.MapGet("", async (TimeFixDbContext db) =>
            await db.Users.OrderBy(u => u.Username)
                .Select(u => new UserDto(u.Username, u.IsAdmin, u.CreatedAt, u.Calendars.Count))
                .ToListAsync());

        admin.MapPost("", async (CreateUserRequest body, UserService users) =>
        {
            User? created = null;
            var result = await Validated(async () =>
                created = await users.CreateAsync(body.Username, body.Password, body.IsAdmin), Results.Ok());
            return created is null
                ? result
                : Results.Created($"/api/admin/users/{created.Username}",
                    new UserDto(created.Username, created.IsAdmin, created.CreatedAt, created.Calendars.Count));
        });

        admin.MapPut("/{username}/password", async (string username, SetPasswordRequest body, UserService users) =>
        {
            var user = await users.FindAsync(username);
            if (user is null) return Results.NotFound();
            return await Validated(() => users.SetPasswordAsync(user, body.Password), Results.NoContent());
        });

        admin.MapDelete("/{username}", async (string username, UserService users, TimeFixDbContext db) =>
        {
            var user = await users.FindAsync(username);
            if (user is null) return Results.NotFound();
            if (user.IsAdmin && await db.Users.CountAsync(u => u.IsAdmin) == 1)
            {
                return Results.Problem("Cannot delete the last administrator.", statusCode: 409);
            }
            db.Users.Remove(user);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });
    }

    private static async Task<IResult> Validated(Func<Task> action, IResult success)
    {
        try
        {
            await action();
            return success;
        }
        catch (UserValidationException e)
        {
            return Results.Problem(e.Message, statusCode: 400);
        }
    }
}
