
using DotNetMvcTest.Data;
using DotNetMvcTest.Models;
using DotNetMvcTest.Services;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

// =====================================================
// CREATE APPLICATION BUILDER
// =====================================================

var builder = WebApplication.CreateBuilder(args);

var connectionString =
    builder.Configuration.GetConnectionString("CashFlowDb")
    ?? throw new InvalidOperationException(
        "Connection string 'CashFlowDb' is not configured.");

// =====================================================
// SERVICES
// =====================================================

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddControllersWithViews();

// ── EF Core InMemory Database (existing Products demo) ────────────
// Intentionally kept on InMemory; the Products feature uses AppDbContext.
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseInMemoryDatabase("ProductsDb"));

// ── ASP.NET Core Identity (SQL Server — CPCL_CashFlow_Local) ──────
// Identity tables (AspNetUsers, AspNetRoles, etc.) live in the same
// SQL Server database alongside the existing Cash Flow tables.
// Cash Flow data is still accessed exclusively via ADO.NET SPs.
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(connectionString));

builder.Services.AddIdentity<IdentityUser, IdentityRole>(options =>
    {
        // Password policy
        options.Password.RequiredLength         = 10;
        options.Password.RequireDigit           = true;
        options.Password.RequireUppercase       = true;
        options.Password.RequireLowercase       = true;
        options.Password.RequireNonAlphanumeric = true;

        // Lockout policy
        options.Lockout.DefaultLockoutTimeSpan  = TimeSpan.FromMinutes(10);
        options.Lockout.MaxFailedAccessAttempts = 5;
        options.Lockout.AllowedForNewUsers      = true;

        // User settings
        options.User.RequireUniqueEmail = true;
        options.SignIn.RequireConfirmedEmail = false;  // No email server in dev
    })
    .AddEntityFrameworkStores<ApplicationDbContext>()
    .AddDefaultTokenProviders();

// Cookie configuration
builder.Services.ConfigureApplicationCookie(options =>
{
    options.LoginPath        = "/Account/Login";
    options.LogoutPath       = "/Account/Logout";
    options.AccessDeniedPath = "/Account/AccessDenied";
    options.Cookie.HttpOnly  = true;
    options.Cookie.SecurePolicy = Microsoft.AspNetCore.Http.CookieSecurePolicy.SameAsRequest;
    options.ExpireTimeSpan   = TimeSpan.FromHours(8);
    options.SlidingExpiration = true;
});

// =====================================================
// BUILD APPLICATION
// =====================================================

var app = builder.Build();

// =====================================================
// TEMPORARY SQL SERVER CONNECTION TEST
// =====================================================

app.MapGet("/api/cashflow/test-connection", async () =>
{
    try
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();
        return Results.Ok(new
        {
            status  = "Success",
            message = "Connected to CPCL_CashFlow_Local"
        });
    }
    catch (SqlException)
    {
        return Results.Problem(
            detail: "SQL Server connection failed. Check the server, database, credentials, and SQL Server availability.",
            statusCode: 500
        );
    }
});

// =====================================================
// MIDDLEWARE
// =====================================================

app.UseSwagger();
app.UseSwaggerUI();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseRouting();

// Authentication MUST come before Authorization
app.UseAuthentication();
app.UseAuthorization();

// .NET 10 static asset configuration
app.MapStaticAssets();

// =====================================================
// MVC ROUTING
// =====================================================

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Dashboard}/{action=Index}/{id?}")
    .WithStaticAssets();

// =====================================================
// API CONTROLLER ROUTING — EXISTING CRUD
// =====================================================

app.MapControllers();

// =====================================================
// EXISTING TEST API
// =====================================================

app.MapGet("/api/test", () =>
{
    return Results.Ok(new
    {
        message = "Hello from .NET 10!",
        status  = "Success"
    });
});

// =====================================================
// SEED SAMPLE PRODUCTS (InMemory)
// =====================================================

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider
        .GetRequiredService<AppDbContext>();

    if (!db.Products.Any())
    {
        db.Products.AddRange(
            new Product { Name = "Keyboard", Price = 1499 },
            new Product { Name = "Mouse",    Price = 699  }
        );

        db.SaveChanges();
    }
}

// =====================================================
// APPLY IDENTITY MIGRATIONS & SEED ROLES / ADMIN
// =====================================================

using (var scope = app.Services.CreateScope())
{
    var logger = scope.ServiceProvider
        .GetRequiredService<ILogger<Program>>();

    try
    {
        // Apply any pending Identity migrations safely
        var identityDb = scope.ServiceProvider
            .GetRequiredService<ApplicationDbContext>();

        await identityDb.Database.MigrateAsync();

        // Seed roles and optional initial administrator
        await IdentitySeeder.SeedAsync(scope.ServiceProvider);
    }
    catch (Exception ex)
    {
        logger.LogError(ex,
            "An error occurred during Identity database migration or seeding. " +
            "The application will still start; fix the database issue and restart.");
    }
}

// =====================================================
// RUN APPLICATION
// =====================================================

app.Run();
