-- ==============================================================================
-- CPCL TREASURY MANAGEMENT SYSTEM - REVISED STORED PROCEDURES (V2)
-- Database: CPCL_CashFlow_Local / CPCL_CashFlow_Test
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. usp_CashFlow_GetCategories
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_CashFlow_GetCategories
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        CategoryId,
        CategoryName,
        SectionName,
        DisplayOrder,
        RowType
    FROM dbo.CashFlowCategories
    WHERE IsActive = 1
    ORDER BY 
        CASE SectionName 
            WHEN N'Inflow' THEN 1 
            WHEN N'Outflow' THEN 2 
            WHEN N'Borrowing' THEN 3 
            ELSE 4 
        END,
        DisplayOrder,
        CategoryId;
END;
GO

-- ------------------------------------------------------------------------------
-- 2. usp_CashFlow_GetStatementGrid
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_CashFlow_GetStatementGrid
    @FinancialYearId INT,
    @FromDate DATE,
    @ToDate DATE,
    @ValueType VARCHAR(12)
AS
BEGIN
    SET NOCOUNT ON;

    -- A. Input Validation
    IF @FinancialYearId IS NULL OR @FinancialYearId <= 0
        THROW 50001, '@FinancialYearId must be a positive integer.', 1;

    IF @FromDate IS NULL OR @ToDate IS NULL
        THROW 50002, '@FromDate and @ToDate cannot be NULL.', 1;

    IF @FromDate > @ToDate
        THROW 50003, '@FromDate must be on or before @ToDate.', 1;

    IF @ValueType IS NULL OR @ValueType NOT IN ('Actual', 'Projected')
        THROW 50004, '@ValueType must be Actual or Projected.', 1;

    -- Validate against configured Financial Year boundaries
    DECLARE @FyStart DATE, @FyEnd DATE;
    SELECT @FyStart = StartDate, @FyEnd = EndDate
    FROM dbo.CashFlowFinancialYears
    WHERE FinancialYearId = @FinancialYearId;

    IF @FyStart IS NULL
        THROW 50005, 'Specified FinancialYearId does not exist in CashFlowFinancialYears.', 1;

    IF @FromDate < @FyStart OR @ToDate > @FyEnd
        THROW 50006, 'Requested date range falls outside the configured financial year boundaries.', 1;

    -- B. Recursive CTE Date Range
    ;WITH DateRange AS
    (
        SELECT @FromDate AS EntryDate
        UNION ALL
        SELECT DATEADD(DAY, 1, EntryDate)
        FROM DateRange
        WHERE EntryDate < @ToDate
    ),
    -- C. Active Detail Lines
    DetailValues AS
    (
        SELECT
            c.CategoryId,
            c.CategoryName,
            c.SectionName,
            c.DisplayOrder,
            c.RowType,
            d.EntryDate,
            v.Amount
        FROM dbo.CashFlowCategories AS c
        CROSS JOIN DateRange AS d
        LEFT JOIN dbo.CashFlowDailyValues AS v
            ON v.CategoryId = c.CategoryId
            AND v.FinancialYearId = @FinancialYearId
            AND v.EntryDate = d.EntryDate
            AND v.ValueType = @ValueType
        WHERE c.IsActive = 1 AND c.RowType = N'Detail'
    ),
    -- D. Total Cash Inflow (Category 42) dynamically aggregated
    InflowTotal AS
    (
        SELECT
            c.CategoryId,
            c.CategoryName,
            c.SectionName,
            c.DisplayOrder,
            c.RowType,
            d.EntryDate,
            COALESCE(SUM(dv.Amount), 0) AS Amount
        FROM dbo.CashFlowCategories AS c
        CROSS JOIN DateRange AS d
        LEFT JOIN DetailValues AS dv
            ON dv.SectionName = N'Inflow'
            AND dv.EntryDate = d.EntryDate
        WHERE c.IsActive = 1 AND c.CategoryId = 42
        GROUP BY c.CategoryId, c.CategoryName, c.SectionName, c.DisplayOrder, c.RowType, d.EntryDate
    ),
    -- E. Total Cash Outflow (Category 70) dynamically aggregated
    OutflowTotal AS
    (
        SELECT
            c.CategoryId,
            c.CategoryName,
            c.SectionName,
            c.DisplayOrder,
            c.RowType,
            d.EntryDate,
            COALESCE(SUM(dv.Amount), 0) AS Amount
        FROM dbo.CashFlowCategories AS c
        CROSS JOIN DateRange AS d
        LEFT JOIN DetailValues AS dv
            ON dv.SectionName = N'Outflow'
            AND dv.EntryDate = d.EntryDate
        WHERE c.IsActive = 1 AND c.CategoryId = 70
        GROUP BY c.CategoryId, c.CategoryName, c.SectionName, c.DisplayOrder, c.RowType, d.EntryDate
    ),
    -- F. Borrowing Subtotals, Totals & Ratios (Categories with Subtotal, Total, Ratio)
    BorrowingSpecialRows AS
    (
        SELECT
            c.CategoryId,
            c.CategoryName,
            c.SectionName,
            c.DisplayOrder,
            c.RowType,
            d.EntryDate,
            v.Amount
        FROM dbo.CashFlowCategories AS c
        CROSS JOIN DateRange AS d
        LEFT JOIN dbo.CashFlowDailyValues AS v
            ON v.CategoryId = c.CategoryId
            AND v.FinancialYearId = @FinancialYearId
            AND v.EntryDate = d.EntryDate
            AND v.ValueType = @ValueType
        WHERE c.IsActive = 1 
          AND c.SectionName = N'Borrowing' 
          AND c.RowType IN (N'Total', N'Subtotal', N'Ratio')
    )
    SELECT CategoryId, CategoryName, SectionName, DisplayOrder, RowType, EntryDate, Amount
    FROM DetailValues
    UNION ALL
    SELECT CategoryId, CategoryName, SectionName, DisplayOrder, RowType, EntryDate, Amount
    FROM InflowTotal
    UNION ALL
    SELECT CategoryId, CategoryName, SectionName, DisplayOrder, RowType, EntryDate, Amount
    FROM OutflowTotal
    UNION ALL
    SELECT CategoryId, CategoryName, SectionName, DisplayOrder, RowType, EntryDate, Amount
    FROM BorrowingSpecialRows
    ORDER BY DisplayOrder, CategoryId, EntryDate
    OPTION (MAXRECURSION 400);
END;
GO

-- ------------------------------------------------------------------------------
-- 3. usp_CashFlow_GetSummary
-- ------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_CashFlow_GetSummary
    @FinancialYearId INT,
    @AsOfDate DATE,
    @ValueType VARCHAR(12)
AS
BEGIN
    SET NOCOUNT ON;

    -- A. Input Validation
    IF @FinancialYearId IS NULL OR @FinancialYearId <= 0
        THROW 50001, '@FinancialYearId must be a positive integer.', 1;

    IF @AsOfDate IS NULL
        THROW 50002, '@AsOfDate cannot be NULL.', 1;

    IF @ValueType IS NULL OR @ValueType NOT IN ('Actual', 'Projected')
        THROW 50003, '@ValueType must be Actual or Projected.', 1;

    -- Validate @AsOfDate against Financial Year boundaries
    DECLARE @FyStart DATE, @FyEnd DATE;
    SELECT @FyStart = StartDate, @FyEnd = EndDate
    FROM dbo.CashFlowFinancialYears
    WHERE FinancialYearId = @FinancialYearId;

    IF @FyStart IS NULL
        THROW 50004, 'Specified FinancialYearId does not exist in CashFlowFinancialYears.', 1;

    IF @AsOfDate < @FyStart OR @AsOfDate > @FyEnd
        THROW 50005, '@AsOfDate falls outside the configured financial year boundaries.', 1;

    -- B. Base Opening Balance at start of financial year
    DECLARE @BaseOpening DECIMAL(19,4) =
        COALESCE((
            SELECT OpeningBalance
            FROM dbo.CashFlowOpeningBalances
            WHERE FinancialYearId = @FinancialYearId
              AND ValueType = @ValueType
        ), 0);

    -- C. Prior Cumulative Receipts (Strictly Active Detail Lines)
    DECLARE @PriorReceipts DECIMAL(19,4) = COALESCE((
        SELECT SUM(v.Amount)
        FROM dbo.CashFlowDailyValues AS v
        INNER JOIN dbo.CashFlowCategories AS c ON c.CategoryId = v.CategoryId
        WHERE v.FinancialYearId = @FinancialYearId
          AND v.EntryDate < @AsOfDate
          AND v.ValueType = @ValueType
          AND c.IsActive = 1
          AND c.SectionName = N'Inflow'
          AND c.RowType = N'Detail'
    ), 0);

    -- D. Prior Cumulative Payments (Strictly Active Detail Lines)
    DECLARE @PriorPayments DECIMAL(19,4) = COALESCE((
        SELECT SUM(v.Amount)
        FROM dbo.CashFlowDailyValues AS v
        INNER JOIN dbo.CashFlowCategories AS c ON c.CategoryId = v.CategoryId
        WHERE v.FinancialYearId = @FinancialYearId
          AND v.EntryDate < @AsOfDate
          AND v.ValueType = @ValueType
          AND c.IsActive = 1
          AND c.SectionName = N'Outflow'
          AND c.RowType = N'Detail'
    ), 0);

    -- E. Daily Opening Balance as of @AsOfDate
    DECLARE @DailyOpening DECIMAL(19,4) = @BaseOpening + @PriorReceipts - @PriorPayments;

    -- F. Current Day Receipts (Strictly Active Detail Lines)
    DECLARE @CurrentReceipts DECIMAL(19,4) = COALESCE((
        SELECT SUM(v.Amount)
        FROM dbo.CashFlowDailyValues AS v
        INNER JOIN dbo.CashFlowCategories AS c ON c.CategoryId = v.CategoryId
        WHERE v.FinancialYearId = @FinancialYearId
          AND v.EntryDate = @AsOfDate
          AND v.ValueType = @ValueType
          AND c.IsActive = 1
          AND c.SectionName = N'Inflow'
          AND c.RowType = N'Detail'
    ), 0);

    -- G. Current Day Payments (Strictly Active Detail Lines)
    DECLARE @CurrentPayments DECIMAL(19,4) = COALESCE((
        SELECT SUM(v.Amount)
        FROM dbo.CashFlowDailyValues AS v
        INNER JOIN dbo.CashFlowCategories AS c ON c.CategoryId = v.CategoryId
        WHERE v.FinancialYearId = @FinancialYearId
          AND v.EntryDate = @AsOfDate
          AND v.ValueType = @ValueType
          AND c.IsActive = 1
          AND c.SectionName = N'Outflow'
          AND c.RowType = N'Detail'
    ), 0);

    -- H. Daily Closing Balance as of @AsOfDate
    DECLARE @DailyClosing DECIMAL(19,4) = @DailyOpening + @CurrentReceipts - @CurrentPayments;

    SELECT
        @DailyOpening AS OpeningBalance,
        @CurrentReceipts AS Receipts,
        @CurrentPayments AS Payments,
        @DailyClosing AS ClosingBalance;
END;
GO
