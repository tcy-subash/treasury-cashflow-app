using DotNetMvcTest.Models;
using Microsoft.EntityFrameworkCore;

namespace DotNetMvcTest.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options)
        : base(options)
    {
    }

    public DbSet<Product> Products => Set<Product>();
}