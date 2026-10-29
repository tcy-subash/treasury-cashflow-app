using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DotNetMvcTest.Controllers;

/// <summary>
/// Executive Dashboard — entry point after login.
/// Accessible to all authenticated users.
/// </summary>
[Authorize]
public class DashboardController : Controller
{
    public IActionResult Index()
    {
        return View();
    }
}
