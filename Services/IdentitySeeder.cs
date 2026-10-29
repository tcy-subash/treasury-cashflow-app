using Microsoft.AspNetCore.Identity;

namespace DotNetMvcTest.Services;

/// <summary>
/// Seeds application roles and the initial administrator account.
///
/// Credentials are read from configuration/environment — never hardcoded.
/// Required keys (set via User Secrets or environment variables):
///
///   AdminSeed:Email     — e.g. admin@cpcl.local
///   AdminSeed:Password  — strong password meeting Identity policy
///
/// The seed is idempotent: safe to call on every startup.
/// If the keys are absent the seeder logs a warning and skips user creation,
/// but roles are always created.
/// </summary>
public sealed class IdentitySeeder
{
    private static readonly string[] Roles =
    {
        "Administrator",
        "TreasuryManager",
        "TreasuryExecutive",
        "Auditor"
    };

    public static async Task SeedAsync(IServiceProvider services)
    {
        var roleManager = services.GetRequiredService<RoleManager<IdentityRole>>();
        var userManager = services.GetRequiredService<UserManager<IdentityUser>>();
        var config      = services.GetRequiredService<IConfiguration>();
        var logger      = services.GetRequiredService<ILogger<IdentitySeeder>>();

        // ── 1. Ensure all roles exist ────────────────────────────────
        foreach (var roleName in Roles)
        {
            if (!await roleManager.RoleExistsAsync(roleName))
            {
                var result = await roleManager.CreateAsync(new IdentityRole(roleName));
                if (result.Succeeded)
                    logger.LogInformation("Role '{Role}' created.", roleName);
                else
                    logger.LogError("Failed to create role '{Role}': {Errors}",
                        roleName, string.Join("; ", result.Errors.Select(e => e.Description)));
            }
        }

        // ── 2. Seed initial administrator ────────────────────────────
        var adminEmail    = config["AdminSeed:Email"];
        var adminPassword = config["AdminSeed:Password"];

        if (string.IsNullOrWhiteSpace(adminEmail) || string.IsNullOrWhiteSpace(adminPassword))
        {
            logger.LogWarning(
                "AdminSeed:Email or AdminSeed:Password is not configured. " +
                "No administrator account was created. " +
                "Set these values in User Secrets or environment variables to provision the initial admin.");
            return;
        }

        var existing = await userManager.FindByEmailAsync(adminEmail);
        if (existing is not null)
        {
            // Admin exists — ensure they have the Administrator role
            if (!await userManager.IsInRoleAsync(existing, "Administrator"))
            {
                await userManager.AddToRoleAsync(existing, "Administrator");
                logger.LogInformation(
                    "Existing user '{Email}' added to Administrator role.", adminEmail);
            }
            return;
        }

        var admin = new IdentityUser
        {
            UserName       = adminEmail,
            Email          = adminEmail,
            EmailConfirmed = true  // Skip email confirmation for the seed account
        };

        var createResult = await userManager.CreateAsync(admin, adminPassword);
        if (!createResult.Succeeded)
        {
            logger.LogError(
                "Failed to create administrator account '{Email}': {Errors}",
                adminEmail,
                string.Join("; ", createResult.Errors.Select(e => e.Description)));
            return;
        }

        await userManager.AddToRoleAsync(admin, "Administrator");
        logger.LogInformation("Administrator account '{Email}' created and seeded.", adminEmail);
    }
}
