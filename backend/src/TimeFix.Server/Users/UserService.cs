using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using TimeFix.Server.Data;

namespace TimeFix.Server.Users;

public class UserValidationException(string message) : Exception(message);

public partial class UserService(TimeFixDbContext db, IPasswordHasher<User> hasher, IConfiguration config)
{
    public const int MinPasswordLength = 8;

    [GeneratedRegex("^[a-z0-9][a-z0-9._-]{1,31}$")]
    private static partial Regex UsernameRegex();

    public static string NormalizeUsername(string username) => username.Trim().ToLowerInvariant();

    public static void ValidateUsername(string username)
    {
        if (!UsernameRegex().IsMatch(username))
        {
            throw new UserValidationException(
                "Username must be 2-32 characters: lower-case letters, digits, '.', '_' or '-'.");
        }
    }

    public static void ValidatePassword(string password)
    {
        if (string.IsNullOrEmpty(password) || password.Length < MinPasswordLength)
        {
            throw new UserValidationException($"Password must be at least {MinPasswordLength} characters.");
        }
    }

    public Task<User?> FindAsync(string username) =>
        db.Users.FirstOrDefaultAsync(u => u.Username == NormalizeUsername(username));

    /// <summary>Creates a user with a default calendar.</summary>
    public async Task<User> CreateAsync(string username, string password, bool isAdmin)
    {
        username = NormalizeUsername(username);
        ValidateUsername(username);
        ValidatePassword(password);
        if (await db.Users.AnyAsync(u => u.Username == username))
        {
            throw new UserValidationException($"User '{username}' already exists.");
        }

        var user = new User { Username = username, PasswordHash = "", IsAdmin = isAdmin };
        user.PasswordHash = hasher.HashPassword(user, password);
        user.Calendars.Add(new Calendar
        {
            Slug = "default",
            DisplayName = config["DefaultCalendarName"] ?? "Personnel",
            Color = "#039BE5",
        });
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return user;
    }

    public async Task SetPasswordAsync(User user, string password)
    {
        ValidatePassword(password);
        user.PasswordHash = hasher.HashPassword(user, password);
        await db.SaveChangesAsync();
    }

    public bool VerifyPassword(User user, string password)
    {
        var result = hasher.VerifyHashedPassword(user, user.PasswordHash, password);
        return result != PasswordVerificationResult.Failed;
    }

    /// <summary>Creates the first administrator from configuration when the database is empty.</summary>
    public async Task BootstrapAdminAsync(ILogger logger)
    {
        if (await db.Users.AnyAsync()) return;
        var username = config["Admin:Username"];
        var password = config["Admin:Password"];
        if (string.IsNullOrWhiteSpace(username) || string.IsNullOrEmpty(password))
        {
            logger.LogWarning(
                "No user exists. Set Admin__Username and Admin__Password to create the first administrator.");
            return;
        }
        await CreateAsync(username, password, isAdmin: true);
        logger.LogInformation("Created administrator '{Username}'.", NormalizeUsername(username));
    }
}
