using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;

namespace DotNetMvcTest.Controllers;

/// <summary>
/// User management — restricted to Administrator role only.
/// </summary>
[Authorize(Roles = "Administrator")]
public class UserManagementController : Controller
{
    private readonly UserManager<IdentityUser> _userManager;
    private readonly RoleManager<IdentityRole> _roleManager;

    public UserManagementController(
        UserManager<IdentityUser> userManager,
        RoleManager<IdentityRole> roleManager)
    {
        _userManager = userManager;
        _roleManager = roleManager;
    }

    public async Task<IActionResult> Index()
    {
        var users = _userManager.Users.ToList();
        var userRoles = new Dictionary<string, IList<string>>();

        foreach (var user in users)
            userRoles[user.Id] = await _userManager.GetRolesAsync(user);

        ViewBag.UserRoles = userRoles;
        ViewBag.AllRoles  = _roleManager.Roles.Select(r => r.Name).ToList();
        return View(users);
    }
}
