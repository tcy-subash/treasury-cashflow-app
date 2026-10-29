using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace DotNetMvcTest.Data;

/// <summary>
/// Identity-enabled DbContext for user/role storage.
/// The existing Cash Flow data lives in CPCL_CashFlow_Local and is
/// accessed exclusively via ADO.NET stored-procedure calls in
/// CashFlowController — nothing here touches those tables.
/// </summary>
public class ApplicationDbContext : IdentityDbContext<IdentityUser>
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        // All Identity tables are created by IdentityDbContext.
        // No Cash Flow entities are mapped here; they are accessed
        // directly through ADO.NET in CashFlowController.
    }
}
