
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// Load env
string? conn = Environment.GetEnvironmentVariable("CONNECTION_STR");
if (string.IsNullOrWhiteSpace(conn))
{
    var dbHost = Environment.GetEnvironmentVariable("DB_HOST") ?? "db";
    var dbPort = Environment.GetEnvironmentVariable("DB_PORT") ?? "5432";
    var dbName = Environment.GetEnvironmentVariable("POSTGRES_DB") ?? "securesign";
    var dbUser = Environment.GetEnvironmentVariable("POSTGRES_USER") ?? "securesign";
    var dbPass = Environment.GetEnvironmentVariable("POSTGRES_PASSWORD") ?? "changeme";
    conn = $"Host={dbHost};Port={dbPort};Database={dbName};Username={dbUser};Password={dbPass}";
}

var jwtSecret = Environment.GetEnvironmentVariable("JWT_SECRET") ?? "devsecret_devsecret_devsecret!";

builder.Services.AddDbContext<AppDb>(opt => opt.UseNpgsql(conn));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = false,
            ValidateAudience = false,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret)),
            ValidateLifetime = true
        };
    });

builder.Services.AddAuthorization();

var app = builder.Build();

// Migrate & seed on startup if flags provided
if (args.Contains("--migrate"))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDb>();
    db.Database.Migrate();

    if (args.Contains("--seed"))
    {
        if (!db.Users.Any())
        {
            var adminEmail = Environment.GetEnvironmentVariable("PLATFORM_ADMIN_EMAIL") ?? "admin@example.com";
            var adminPwd = Environment.GetEnvironmentVariable("PLATFORM_ADMIN_PWD") ?? "Admin123!";
            db.Users.Add(new User
            {
                Id = Guid.NewGuid(),
                Email = adminEmail,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(adminPwd),
                CreatedAt = DateTimeOffset.UtcNow
            });
            db.SaveChanges();
            Console.WriteLine($"Seeded admin user: {adminEmail}");
        }
    }
}

// Swagger for dev
app.UseSwagger();
app.UseSwaggerUI();

app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/api/health", () => new { status = "ok", time = DateTimeOffset.UtcNow });

// Auth minimal (email/password demo only)
app.MapPost("/api/auth/register", async (AppDb db, RegisterDto dto) =>
{
    if (await db.Users.AnyAsync(u => u.Email == dto.Email)) return Results.Conflict("Email exists");
    var user = new User { Id = Guid.NewGuid(), Email = dto.Email, PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.Password), CreatedAt = DateTimeOffset.UtcNow };
    db.Users.Add(user);
    await db.SaveChangesAsync();
    return Results.Ok(new { user.Id, user.Email });
});

app.MapPost("/api/auth/login", async (AppDb db, LoginDto dto) =>
{
    var user = await db.Users.FirstOrDefaultAsync(u => u.Email == dto.Email);
    if (user == null || !BCrypt.Net.BCrypt.Verify(dto.Password, user.PasswordHash)) return Results.Unauthorized();

    var token = JwtHelper.GenerateToken(user.Id.ToString(), dto.Email, jwtSecret);
    return Results.Ok(new { token });
});

// Tenants (simplified)
app.MapPost("/api/tenants", async (AppDb db, TenantCreateDto dto) =>
{
    var t = new Tenant { Id = Guid.NewGuid(), Name = dto.Name, Slug = dto.Slug, Plan = dto.Plan ?? "free", CreatedAt = DateTimeOffset.UtcNow };
    db.Tenants.Add(t);
    await db.SaveChangesAsync();
    return Results.Ok(new { t.Id, t.Name, t.Slug, t.Plan });
});

app.Run();

// --- Models/EF ---
public class AppDb : DbContext
{
    public AppDb(DbContextOptions<AppDb> options) : base(options) { }
    public DbSet<User> Users => Set<User>();
    public DbSet<Tenant> Tenants => Set<Tenant>();
    protected override void OnModelCreating(ModelBuilder b)
    {
        b.HasPostgresExtension("uuid-ossp");
        b.Entity<User>().HasIndex(x => x.Email).IsUnique();
        base.OnModelCreating(b);
    }
}
public class User
{
    public Guid Id { get; set; }
    public string Email { get; set; } = default!;
    public string PasswordHash { get; set; } = default!;
    public DateTimeOffset CreatedAt { get; set; }
}
public class Tenant
{
    public Guid Id { get; set; }
    public string Name { get; set; } = default!;
    public string Slug { get; set; } = default!;
    public string Plan { get; set; } = "free";
    public DateTimeOffset CreatedAt { get; set; }
}

public record RegisterDto(string Email, string Password);
public record LoginDto(string Email, string Password);
public record TenantCreateDto(string Name, string Slug, string? Plan);

// --- JWT helper ---
static class JwtHelper
{
    public static string GenerateToken(string userId, string email, string secret)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
        var token = handler.CreateJwtSecurityToken(
            claims: new[] { new Claim(ClaimTypes.NameIdentifier, userId), new Claim(ClaimTypes.Email, email) },
            expires: DateTime.UtcNow.AddHours(8),
            signingCredentials: creds
        );
        return handler.WriteToken(token);
    }
}
