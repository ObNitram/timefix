using Microsoft.EntityFrameworkCore;

namespace TimeFix.Server.Data;

public enum DatabaseProvider { Sqlite, Postgres }

public static class DatabaseSetup
{
    /// <summary>
    /// Registers the DbContext for the provider selected by
    /// <c>Database:Provider</c> (Sqlite | Postgres) and
    /// <c>Database:ConnectionString</c>.
    /// </summary>
    public static IServiceCollection AddTimeFixDatabase(this IServiceCollection services, IConfiguration config)
    {
        var providerName = config["Database:Provider"] ?? "Sqlite";
        if (!Enum.TryParse<DatabaseProvider>(providerName, ignoreCase: true, out var provider))
        {
            throw new InvalidOperationException(
                $"Unknown Database:Provider '{providerName}'. Use 'Sqlite' or 'Postgres'.");
        }

        var connectionString = config["Database:ConnectionString"];
        switch (provider)
        {
            case DatabaseProvider.Sqlite:
                connectionString ??= "Data Source=/data/timefix.db";
                services.AddDbContext<SqliteTimeFixDbContext>(o => o.UseSqlite(connectionString));
                services.AddScoped<TimeFixDbContext>(sp => sp.GetRequiredService<SqliteTimeFixDbContext>());
                break;
            case DatabaseProvider.Postgres:
                if (string.IsNullOrWhiteSpace(connectionString))
                {
                    throw new InvalidOperationException(
                        "Database:ConnectionString is required for PostgreSQL.");
                }
                services.AddDbContext<PostgresTimeFixDbContext>(o => o.UseNpgsql(connectionString));
                services.AddScoped<TimeFixDbContext>(sp => sp.GetRequiredService<PostgresTimeFixDbContext>());
                break;
        }
        return services;
    }

    /// <summary>Applies pending migrations (creating the SQLite folder if needed).</summary>
    public static async Task MigrateAsync(IServiceProvider services, ILogger logger)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<TimeFixDbContext>();
        if (db.Database.IsSqlite())
        {
            var source = new Microsoft.Data.Sqlite.SqliteConnectionStringBuilder(
                db.Database.GetConnectionString()).DataSource;
            var dir = Path.GetDirectoryName(Path.GetFullPath(source));
            if (!string.IsNullOrEmpty(dir) && source != ":memory:") Directory.CreateDirectory(dir);
        }
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                await db.Database.MigrateAsync();
                return;
            }
            catch (Exception e) when (attempt < 10 && db.Database.IsNpgsql())
            {
                // The PostgreSQL container may still be starting.
                logger.LogWarning("Database not ready ({Message}), retrying…", e.Message);
                await Task.Delay(TimeSpan.FromSeconds(3));
            }
        }
    }
}
