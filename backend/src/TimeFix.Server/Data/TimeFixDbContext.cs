using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace TimeFix.Server.Data;

/// <summary>
/// Shared model. Each database provider has its own subclass so that EF Core
/// migrations can be generated and applied per provider.
/// </summary>
public abstract class TimeFixDbContext(DbContextOptions options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Calendar> Calendars => Set<Calendar>();
    public DbSet<CalendarObject> CalendarObjects => Set<CalendarObject>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>(e =>
        {
            e.HasIndex(u => u.Username).IsUnique();
            e.Property(u => u.Username).HasMaxLength(64);
            e.Property(u => u.PasswordHash).HasMaxLength(512);
        });

        b.Entity<Calendar>(e =>
        {
            e.HasIndex(c => new { c.OwnerId, c.Slug }).IsUnique();
            e.Property(c => c.Slug).HasMaxLength(128);
            e.Property(c => c.DisplayName).HasMaxLength(256);
            e.Property(c => c.Color).HasMaxLength(16);
            e.HasOne(c => c.Owner).WithMany(u => u.Calendars)
                .HasForeignKey(c => c.OwnerId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<CalendarObject>(e =>
        {
            e.HasIndex(o => new { o.CalendarId, o.Name }).IsUnique();
            e.HasIndex(o => new { o.CalendarId, o.Uid }).IsUnique();
            e.Property(o => o.Name).HasMaxLength(256);
            e.Property(o => o.Uid).HasMaxLength(512);
            e.Property(o => o.ComponentType).HasMaxLength(16);
            e.Property(o => o.ETag).HasMaxLength(80);
            e.HasOne(o => o.Calendar).WithMany(c => c.Objects)
                .HasForeignKey(o => o.CalendarId).OnDelete(DeleteBehavior.Cascade);
        });
    }
}

public sealed class SqliteTimeFixDbContext(DbContextOptions<SqliteTimeFixDbContext> options)
    : TimeFixDbContext(options);

public sealed class PostgresTimeFixDbContext(DbContextOptions<PostgresTimeFixDbContext> options)
    : TimeFixDbContext(options);

// Design-time factories used by `dotnet ef migrations add`.
public sealed class SqliteDesignFactory : IDesignTimeDbContextFactory<SqliteTimeFixDbContext>
{
    public SqliteTimeFixDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<SqliteTimeFixDbContext>()
            .UseSqlite("Data Source=design.db").Options);
}

public sealed class PostgresDesignFactory : IDesignTimeDbContextFactory<PostgresTimeFixDbContext>
{
    public PostgresTimeFixDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<PostgresTimeFixDbContext>()
            .UseNpgsql("Host=localhost;Database=design").Options);
}
