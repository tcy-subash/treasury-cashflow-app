
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DotNetMvcTest.Controllers
{
    [Authorize(Roles = "Administrator,TreasuryManager,TreasuryExecutive,Auditor")]
    public class CashFlowPageController : Controller
    {
        // king
        public IActionResult Index()
        {
            return View("/Views/CashFlowPage/Index.cshtml");
        }
    }
}
