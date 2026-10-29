using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DotNetMvcTest.Controllers;

/// <summary>
/// Placeholder — Borrowings &amp; Facilities module (not yet implemented).
/// </summary>
[Authorize(Roles = "Administrator,TreasuryManager,TreasuryExecutive")]
public class BorrowingsController : Controller
{
    public IActionResult Index() => View();
}

/// <summary>
/// Placeholder — Investments &amp; Repayments module (not yet implemented).
/// </summary>
[Authorize(Roles = "Administrator,TreasuryManager,TreasuryExecutive")]
public class InvestmentsController : Controller
{
    public IActionResult Index() => View();
}

/// <summary>
/// Placeholder — Reconciliation module (not yet implemented).
/// </summary>
[Authorize(Roles = "Administrator,TreasuryManager,TreasuryExecutive,Auditor")]
public class ReconciliationController : Controller
{
    public IActionResult Index() => View();
}
