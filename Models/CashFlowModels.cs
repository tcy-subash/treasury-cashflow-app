using System.ComponentModel.DataAnnotations;

namespace DotNetMvcTest.Models
{
    public class SaveBatchRequest
    {
        [Required]
        [Range(1, int.MaxValue, ErrorMessage = "FinancialYearId must be positive.")]
        public int FinancialYearId { get; set; } = 1;

        [Required(ErrorMessage = "PR number is mandatory.")]
        [StringLength(100, MinimumLength = 1, ErrorMessage = "PR number cannot exceed 100 characters.")]
        public string PrNumber { get; set; } = string.Empty;

        [Required(ErrorMessage = "Remark is mandatory.")]
        [StringLength(1000, MinimumLength = 1, ErrorMessage = "Remark cannot exceed 1000 characters.")]
        public string Remark { get; set; } = string.Empty;

        [Required(ErrorMessage = "At least one cell change must be submitted.")]
        [MinLength(1, ErrorMessage = "Submission batch must contain at least one cell change.")]
        public List<SaveCellItem> Cells { get; set; } = new();
    }

    public class SaveCellItem
    {
        [Range(1, int.MaxValue, ErrorMessage = "Valid CategoryId is required.")]
        public int CategoryId { get; set; }

        [Required(ErrorMessage = "EntryDate is required.")]
        public DateTime EntryDate { get; set; }

        [Required(ErrorMessage = "ValueType is required.")]
        [RegularExpression("^(Actual|Projected)$", ErrorMessage = "ValueType must be Actual or Projected.")]
        public string ValueType { get; set; } = "Actual";

        [Range(0, 999999999999999.9999, ErrorMessage = "Amount must be non-negative and within valid limits.")]
        public decimal? NewAmount { get; set; }

        /// <summary>
        /// Base64-encoded 8-byte rowversion token. Null for newly entered cells.
        /// </summary>
        public string? RowVersion { get; set; }
    }

    public class SaveBatchResponse
    {
        public bool Success { get; set; }
        public Guid BatchId { get; set; }
        public int RowsModified { get; set; }
        public string Message { get; set; } = string.Empty;
    }

    public class AuditHistoryItem
    {
        public long AuditLogId { get; set; }
        public Guid BatchId { get; set; }
        public int FinancialYearId { get; set; }
        public int CategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public string SectionName { get; set; } = string.Empty;
        public DateTime EntryDate { get; set; }
        public string ValueType { get; set; } = string.Empty;
        public decimal? OldAmount { get; set; }
        public decimal? NewAmount { get; set; }
        public string PrNumber { get; set; } = string.Empty;
        public string Remark { get; set; } = string.Empty;
        public string ModifiedByUserId { get; set; } = string.Empty;
        public string ModifiedByEmail { get; set; } = string.Empty;
        public DateTime ModifiedAtUtc { get; set; }
    }

    public class AuditHistoryResponse
    {
        public int TotalCount { get; set; }
        public int PageNumber { get; set; }
        public int PageSize { get; set; }
        public List<AuditHistoryItem> Items { get; set; } = new();
    }
}
