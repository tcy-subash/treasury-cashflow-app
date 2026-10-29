using System.Data;
using System.Security.Claims;
using DotNetMvcTest.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace DotNetMvcTest.Controllers
{
    [ApiController]
    [Route("api/cashflow")]
    [Authorize(Roles = "Administrator,TreasuryManager,TreasuryExecutive,Auditor")]
    public class CashFlowController : ControllerBase
    {
        private readonly IConfiguration _configuration;
        private readonly UserManager<IdentityUser> _userManager;

        public CashFlowController(
            IConfiguration configuration,
            UserManager<IdentityUser> userManager)
        {
            _configuration = configuration;
            _userManager = userManager;
        }

        private SqlConnection CreateConnection()
        {
            var connectionString =
                _configuration.GetConnectionString("CashFlowDb");

            if (string.IsNullOrWhiteSpace(connectionString))
            {
                throw new InvalidOperationException(
                    "Connection string 'CashFlowDb' is not configured.");
            }

            return new SqlConnection(connectionString);
        }

        private static async Task<List<Dictionary<string, object?>>> ReadRowsAsync(
            SqlDataReader reader)
        {
            var results = new List<Dictionary<string, object?>>();

            while (await reader.ReadAsync())
            {
                var row = new Dictionary<string, object?>();

                for (int i = 0; i < reader.FieldCount; i++)
                {
                    var colName = reader.GetName(i);
                    if (reader.IsDBNull(i))
                    {
                        row[colName] = null;
                    }
                    else
                    {
                        var val = reader.GetValue(i);
                        // Encode RowVersion as Base64 string for clean JSON transport
                        if (val is byte[] bytes && string.Equals(colName, "RowVersion", StringComparison.OrdinalIgnoreCase))
                        {
                            row[colName] = Convert.ToBase64String(bytes);
                        }
                        else
                        {
                            row[colName] = val;
                        }
                    }
                }

                results.Add(row);
            }

            return results;
        }

        [HttpGet("categories")]
        public async Task<IActionResult> GetCategories()
        {
            await using var connection = CreateConnection();

            await using var command = new SqlCommand(
                "dbo.usp_CashFlow_GetCategories", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            await connection.OpenAsync();

            await using var reader = await command.ExecuteReaderAsync();

            var categories = new List<object>();

            while (await reader.ReadAsync())
            {
                categories.Add(new
                {
                    categoryId = reader.GetInt32(
                        reader.GetOrdinal("CategoryId")),

                    categoryName = reader.GetString(
                        reader.GetOrdinal("CategoryName"))
                });
            }

            return Ok(categories);
        }

        [HttpGet("statement-grid")]
        public async Task<IActionResult> GetStatementGrid(
            [FromQuery] int financialYearId,
            [FromQuery] DateTime fromDate,
            [FromQuery] DateTime toDate,
            [FromQuery] string valueType = "Actual")
        {
            if (financialYearId <= 0)
                return BadRequest("Financial year ID must be greater than zero.");

            if (fromDate.Date > toDate.Date)
                return BadRequest("From date must be on or before to date.");

            if (valueType != "Actual" && valueType != "Projected")
                return BadRequest("Value type must be Actual or Projected.");

            await using var connection = CreateConnection();

            await using var command = new SqlCommand(
                "dbo.usp_CashFlow_GetStatementGrid", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@FinancialYearId", SqlDbType.Int).Value = financialYearId;

            command.Parameters.Add(
                "@FromDate", SqlDbType.Date).Value = fromDate.Date;

            command.Parameters.Add(
                "@ToDate", SqlDbType.Date).Value = toDate.Date;

            command.Parameters.Add(
                "@ValueType", SqlDbType.VarChar, 12).Value = valueType;

            await connection.OpenAsync();

            await using var reader = await command.ExecuteReaderAsync();

            return Ok(await ReadRowsAsync(reader));
        }

        [HttpGet("summary")]
        public async Task<IActionResult> GetSummary(
            [FromQuery] int financialYearId,
            [FromQuery] DateTime asOfDate,
            [FromQuery] string valueType = "Actual")
        {
            if (financialYearId <= 0)
                return BadRequest("Financial year ID must be greater than zero.");

            if (valueType != "Actual" && valueType != "Projected")
                return BadRequest("Value type must be Actual or Projected.");

            await using var connection = CreateConnection();

            await using var command = new SqlCommand(
                "dbo.usp_CashFlow_GetSummary", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@FinancialYearId", SqlDbType.Int).Value = financialYearId;

            command.Parameters.Add(
                "@AsOfDate", SqlDbType.Date).Value = asOfDate.Date;

            command.Parameters.Add(
                "@ValueType", SqlDbType.VarChar, 12).Value = valueType;

            await connection.OpenAsync();

            await using var reader = await command.ExecuteReaderAsync();

            return Ok(await ReadRowsAsync(reader));
        }

        [HttpGet("transactions")]
        public async Task<IActionResult> GetTransactions(
            [FromQuery] int financialYearId)
        {
            if (financialYearId <= 0)
                return BadRequest("Financial year ID must be greater than zero.");

            await using var connection = CreateConnection();

            await using var command = new SqlCommand(
                "dbo.usp_CashFlow_GetTransactions", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@FinancialYearId", SqlDbType.Int).Value = financialYearId;

            await connection.OpenAsync();

            await using var reader = await command.ExecuteReaderAsync();

            return Ok(await ReadRowsAsync(reader));
        }

        [HttpGet("projected-amounts")]
        public async Task<IActionResult> GetProjectedAmounts(
            [FromQuery] int financialYearId)
        {
            if (financialYearId <= 0)
                return BadRequest("Financial year ID must be greater than zero.");

            await using var connection = CreateConnection();

            await using var command = new SqlCommand(
                "dbo.usp_CashFlow_GetProjectedAmounts", connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            command.Parameters.Add(
                "@FinancialYearId", SqlDbType.Int).Value = financialYearId;

            await connection.OpenAsync();

            await using var reader = await command.ExecuteReaderAsync();

            return Ok(await ReadRowsAsync(reader));
        }

        // =================================================================
        // BATCH SAVE ENDPOINT
        // Authorized: Administrator, TreasuryManager, TreasuryExecutive
        // Strictly Denied: Auditor
        // =================================================================
        [HttpPost("save")]
        [Authorize(Roles = "Administrator,TreasuryManager,TreasuryExecutive")]
        public async Task<IActionResult> SaveBatch([FromBody] SaveBatchRequest request)
        {
            if (!ModelState.IsValid)
            {
                return BadRequest(new { success = false, error = "Invalid submission parameters.", details = ModelState });
            }

            if (request.Cells == null || request.Cells.Count == 0)
            {
                return BadRequest(new { success = false, error = "At least one cell change must be submitted." });
            }

            // 1. Resolve Identity strictly from authenticated principal
            var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
            var userEmail = User.FindFirstValue(ClaimTypes.Email);

            if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(userEmail))
            {
                var user = await _userManager.GetUserAsync(User);
                if (user != null)
                {
                    userId ??= user.Id;
                    userEmail ??= user.Email;
                }
            }

            if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(userEmail))
            {
                return Unauthorized(new { success = false, error = "Authenticated user identity or verified email could not be resolved." });
            }

            // 2. Build Table-Valued Parameter DataTable
            var cellDataTable = new DataTable();
            cellDataTable.Columns.Add("CategoryId", typeof(int));
            cellDataTable.Columns.Add("EntryDate", typeof(DateTime));
            cellDataTable.Columns.Add("ValueType", typeof(string));
            var colAmount = new DataColumn("NewAmount", typeof(decimal)) { AllowDBNull = true };
            var colRowVersion = new DataColumn("RowVersion", typeof(byte[])) { AllowDBNull = true };
            cellDataTable.Columns.Add(colAmount);
            cellDataTable.Columns.Add(colRowVersion);

            var seenKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var cell in request.Cells)
            {
                var key = $"{cell.CategoryId}_{cell.EntryDate:yyyy-MM-dd}_{cell.ValueType}";
                if (!seenKeys.Add(key))
                {
                    return BadRequest(new { success = false, error = $"Duplicate cell in batch: Category {cell.CategoryId} for {cell.EntryDate:yyyy-MM-dd} ({cell.ValueType})." });
                }

                byte[]? rowVersionBytes = null;
                if (!string.IsNullOrWhiteSpace(cell.RowVersion))
                {
                    try
                    {
                        rowVersionBytes = Convert.FromBase64String(cell.RowVersion);
                        if (rowVersionBytes.Length != 8)
                        {
                            return BadRequest(new { success = false, error = "Invalid RowVersion token: Must be exactly 8 bytes." });
                        }
                    }
                    catch (FormatException)
                    {
                        return BadRequest(new { success = false, error = "Invalid RowVersion token format: Base64 decoding failed." });
                    }
                }

                cellDataTable.Rows.Add(
                    cell.CategoryId,
                    cell.EntryDate.Date,
                    cell.ValueType,
                    cell.NewAmount.HasValue ? (object)cell.NewAmount.Value : DBNull.Value,
                    rowVersionBytes != null ? (object)rowVersionBytes : DBNull.Value
                );
            }

            // 3. Execute usp_CashFlow_SaveBatch
            var batchId = Guid.NewGuid();

            try
            {
                await using var connection = CreateConnection();
                await using var command = new SqlCommand("dbo.usp_CashFlow_SaveBatch", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.Add("@FinancialYearId", SqlDbType.Int).Value = request.FinancialYearId;
                command.Parameters.Add("@PrNumber", SqlDbType.NVarChar, 100).Value = request.PrNumber.Trim();
                command.Parameters.Add("@Remark", SqlDbType.NVarChar, 1000).Value = request.Remark.Trim();
                command.Parameters.Add("@ModifiedByUserId", SqlDbType.NVarChar, 450).Value = userId;
                command.Parameters.Add("@ModifiedByEmail", SqlDbType.NVarChar, 256).Value = userEmail;
                command.Parameters.Add("@BatchId", SqlDbType.UniqueIdentifier).Value = batchId;

                var tvp = command.Parameters.AddWithValue("@Cells", cellDataTable);
                tvp.SqlDbType = SqlDbType.Structured;
                tvp.TypeName = "dbo.CashFlowCellSaveType";

                await connection.OpenAsync();
                await using var reader = await command.ExecuteReaderAsync();

                int rowsModified = 0;
                if (await reader.ReadAsync())
                {
                    rowsModified = reader.GetInt32(reader.GetOrdinal("RowsModified"));
                }

                return Ok(new SaveBatchResponse
                {
                    Success = true,
                    BatchId = batchId,
                    RowsModified = rowsModified,
                    Message = rowsModified > 0
                        ? $"Successfully persisted {rowsModified} cell change(s)."
                        : "No changes detected. Submitted values matched existing records."
                });
            }
            catch (SqlException ex)
            {
                // Concurrency conflicts
                if (ex.Number == 50001 || ex.Number == 50002)
                {
                    return Conflict(new { success = false, error = ex.Message, code = ex.Number });
                }

                // Business validation errors
                if (ex.Number >= 50000 && ex.Number <= 50010)
                {
                    return BadRequest(new { success = false, error = ex.Message, code = ex.Number });
                }

                return StatusCode(500, new { success = false, error = $"Database error during batch save: {ex.Message}" });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { success = false, error = $"Unexpected error during batch save: {ex.Message}" });
            }
        }

        // =================================================================
        // AUDIT HISTORY ENDPOINT
        // Authorized: Administrator, TreasuryManager, Auditor
        // Denied: TreasuryExecutive
        // =================================================================
        [HttpGet("audit")]
        [Authorize(Roles = "Administrator,TreasuryManager,Auditor")]
        public async Task<IActionResult> GetAuditHistory(
            [FromQuery] int financialYearId = 1,
            [FromQuery] string? prNumber = null,
            [FromQuery] DateTime? fromDate = null,
            [FromQuery] DateTime? toDate = null,
            [FromQuery] int? categoryId = null,
            [FromQuery] string? valueType = null,
            [FromQuery] int pageNumber = 1,
            [FromQuery] int pageSize = 50)
        {
            if (financialYearId <= 0)
                return BadRequest("Financial year ID must be greater than zero.");

            if (fromDate.HasValue && toDate.HasValue && fromDate.Value.Date > toDate.Value.Date)
                return BadRequest("From date must be on or before to date.");

            if (!string.IsNullOrWhiteSpace(valueType) && valueType != "Actual" && valueType != "Projected")
                return BadRequest("Value type filter must be Actual or Projected.");

            if (pageNumber < 1) pageNumber = 1;
            if (pageSize < 1 || pageSize > 200) pageSize = 50;

            try
            {
                await using var connection = CreateConnection();
                await using var command = new SqlCommand("dbo.usp_CashFlow_GetAuditHistory", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                command.Parameters.Add("@FinancialYearId", SqlDbType.Int).Value = financialYearId;
                command.Parameters.Add("@PrNumber", SqlDbType.NVarChar, 100).Value =
                    string.IsNullOrWhiteSpace(prNumber) ? DBNull.Value : prNumber.Trim();
                command.Parameters.Add("@FromDate", SqlDbType.Date).Value =
                    fromDate.HasValue ? fromDate.Value.Date : DBNull.Value;
                command.Parameters.Add("@ToDate", SqlDbType.Date).Value =
                    toDate.HasValue ? toDate.Value.Date : DBNull.Value;
                command.Parameters.Add("@CategoryId", SqlDbType.Int).Value =
                    categoryId.HasValue && categoryId.Value > 0 ? categoryId.Value : DBNull.Value;
                command.Parameters.Add("@ValueType", SqlDbType.VarChar, 12).Value =
                    string.IsNullOrWhiteSpace(valueType) ? DBNull.Value : valueType.Trim();
                command.Parameters.Add("@PageNumber", SqlDbType.Int).Value = pageNumber;
                command.Parameters.Add("@PageSize", SqlDbType.Int).Value = pageSize;

                await connection.OpenAsync();
                await using var reader = await command.ExecuteReaderAsync();

                // 1. First result set: Total Count
                int totalCount = 0;
                if (await reader.ReadAsync())
                {
                    totalCount = reader.GetInt32(reader.GetOrdinal("TotalCount"));
                }

                // 2. Second result set: Paged items
                var items = new List<AuditHistoryItem>();
                if (await reader.NextResultAsync())
                {
                    while (await reader.ReadAsync())
                    {
                        items.Add(new AuditHistoryItem
                        {
                            AuditLogId = reader.GetInt64(reader.GetOrdinal("AuditLogId")),
                            BatchId = reader.GetGuid(reader.GetOrdinal("BatchId")),
                            FinancialYearId = reader.GetInt32(reader.GetOrdinal("FinancialYearId")),
                            CategoryId = reader.GetInt32(reader.GetOrdinal("CategoryId")),
                            CategoryName = reader.GetString(reader.GetOrdinal("CategoryName")),
                            SectionName = reader.GetString(reader.GetOrdinal("SectionName")),
                            EntryDate = reader.GetDateTime(reader.GetOrdinal("EntryDate")),
                            ValueType = reader.GetString(reader.GetOrdinal("ValueType")),
                            OldAmount = reader.IsDBNull(reader.GetOrdinal("OldAmount")) ? null : reader.GetDecimal(reader.GetOrdinal("OldAmount")),
                            NewAmount = reader.IsDBNull(reader.GetOrdinal("NewAmount")) ? null : reader.GetDecimal(reader.GetOrdinal("NewAmount")),
                            PrNumber = reader.GetString(reader.GetOrdinal("PrNumber")),
                            Remark = reader.GetString(reader.GetOrdinal("Remark")),
                            ModifiedByUserId = reader.GetString(reader.GetOrdinal("ModifiedByUserId")),
                            ModifiedByEmail = reader.GetString(reader.GetOrdinal("ModifiedByEmail")),
                            ModifiedAtUtc = reader.GetDateTime(reader.GetOrdinal("ModifiedAtUtc"))
                        });
                    }
                }

                return Ok(new AuditHistoryResponse
                {
                    TotalCount = totalCount,
                    PageNumber = pageNumber,
                    PageSize = pageSize,
                    Items = items
                });
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000 && ex.Number <= 50010)
                {
                    return BadRequest(new { success = false, error = ex.Message });
                }
                return StatusCode(500, new { success = false, error = $"Database error: {ex.Message}" });
            }
        }
    }
}
