-- =====================================================================
-- CPCL Treasury Cash Flow — Editing, Batch Persistence & Audit Migration
-- Database: CPCL_CashFlow_Local
-- Fully idempotent, non-destructive, rerunnable
-- =====================================================================
USE [CPCL_CashFlow_Local];
GO

-- ---------------------------------------------------------------------
-- 1. Optimistic Concurrency Token on CashFlowDailyValues
-- ---------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo' 
      AND TABLE_NAME = 'CashFlowDailyValues' 
      AND COLUMN_NAME = 'RowVersion'
)
BEGIN
    ALTER TABLE dbo.CashFlowDailyValues
    ADD [RowVersion] rowversion NOT NULL;
END
GO

-- ---------------------------------------------------------------------
-- 2. Audit Trail Table: CashFlowAuditLog
-- ---------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'CashFlowAuditLog'
)
BEGIN
    CREATE TABLE dbo.CashFlowAuditLog
    (
        AuditLogId       BIGINT IDENTITY(1,1) NOT NULL,
        BatchId          UNIQUEIDENTIFIER     NOT NULL,
        FinancialYearId  INT                  NOT NULL,
        CategoryId       INT                  NOT NULL,
        EntryDate        DATE                 NOT NULL,
        ValueType        VARCHAR(12)          NOT NULL,
        OldAmount        DECIMAL(19,4)        NULL,
        NewAmount        DECIMAL(19,4)        NULL,
        PrNumber         NVARCHAR(100)        NOT NULL,
        Remark           NVARCHAR(1000)       NOT NULL,
        ModifiedByUserId NVARCHAR(450)        NOT NULL,
        ModifiedByEmail  NVARCHAR(256)        NOT NULL,
        ModifiedAtUtc    DATETIME2(7)         NOT NULL CONSTRAINT DF_CashFlowAuditLog_ModifiedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_CashFlowAuditLog PRIMARY KEY CLUSTERED (AuditLogId ASC),
        CONSTRAINT FK_CashFlowAuditLog_FinancialYears FOREIGN KEY (FinancialYearId) REFERENCES dbo.CashFlowFinancialYears(FinancialYearId),
        CONSTRAINT FK_CashFlowAuditLog_Categories FOREIGN KEY (CategoryId) REFERENCES dbo.CashFlowCategories(CategoryId)
    );

    CREATE NONCLUSTERED INDEX IX_CashFlowAuditLog_PrNumber 
        ON dbo.CashFlowAuditLog (PrNumber, ModifiedAtUtc DESC);

    CREATE NONCLUSTERED INDEX IX_CashFlowAuditLog_Filter 
        ON dbo.CashFlowAuditLog (FinancialYearId, EntryDate, CategoryId, ValueType)
        INCLUDE (BatchId, OldAmount, NewAmount, ModifiedAtUtc);

    CREATE NONCLUSTERED INDEX IX_CashFlowAuditLog_BatchId 
        ON dbo.CashFlowAuditLog (BatchId);
END
GO

-- ---------------------------------------------------------------------
-- 3. Table-Valued Parameter Type (Idempotent Creation)
-- ---------------------------------------------------------------------
IF TYPE_ID('dbo.CashFlowCellSaveType') IS NULL
BEGIN
    CREATE TYPE dbo.CashFlowCellSaveType AS TABLE
    (
        CategoryId INT           NOT NULL,
        EntryDate  DATE          NOT NULL,
        ValueType  VARCHAR(12)   NOT NULL,
        NewAmount  DECIMAL(19,4) NULL,
        RowVersion BINARY(8)     NULL   -- Exact rowversion token; NULL for new cell
    );
END
GO

-- ---------------------------------------------------------------------
-- 4. Stored Procedure: Batch Save with Strict Validation & Audit Logging
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_CashFlow_SaveBatch
    @FinancialYearId  INT,
    @PrNumber         NVARCHAR(100),
    @Remark           NVARCHAR(1000),
    @ModifiedByUserId NVARCHAR(450),
    @ModifiedByEmail  NVARCHAR(256),
    @BatchId          UNIQUEIDENTIFIER,
    @Cells            dbo.CashFlowCellSaveType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- -----------------------------------------------------------------
    -- 1. Pre-Transaction Validations
    -- -----------------------------------------------------------------
    IF @FinancialYearId <= 0
        THROW 50003, 'Invalid FinancialYearId. Must be greater than zero.', 1;

    IF LTRIM(RTRIM(ISNULL(@PrNumber, ''))) = ''
        THROW 50003, 'PR number is mandatory.', 1;

    IF LTRIM(RTRIM(ISNULL(@Remark, ''))) = ''
        THROW 50003, 'Remark is mandatory for every save batch.', 1;

    IF LTRIM(RTRIM(ISNULL(@ModifiedByUserId, ''))) = '' OR LTRIM(RTRIM(ISNULL(@ModifiedByEmail, ''))) = ''
        THROW 50003, 'Authenticated identity context is required. Save rejected.', 1;

    IF NOT EXISTS (SELECT 1 FROM @Cells)
        THROW 50004, 'Submission batch is empty. No cells provided.', 1;

    -- Reject duplicate cells within submission
    IF EXISTS (
        SELECT CategoryId, EntryDate, ValueType 
        FROM @Cells 
        GROUP BY CategoryId, EntryDate, ValueType 
        HAVING COUNT(*) > 1
    )
        THROW 50003, 'Duplicate cell entries detected in submission batch.', 1;

    -- Validate FY Date Range
    DECLARE @FyStart DATE, @FyEnd DATE;
    SELECT @FyStart = StartDate, @FyEnd = EndDate 
    FROM dbo.CashFlowFinancialYears 
    WHERE FinancialYearId = @FinancialYearId;

    IF @FyStart IS NULL
        THROW 50003, 'Financial year does not exist.', 1;

    IF EXISTS (
        SELECT 1 FROM @Cells 
        WHERE EntryDate < @FyStart OR EntryDate > @FyEnd
    )
        THROW 50003, 'One or more cell dates fall outside the financial year boundaries.', 1;

    -- Validate Categories: Must exist, be active, and be 'Detail' type
    IF EXISTS (
        SELECT 1 
        FROM @Cells c
        LEFT JOIN dbo.CashFlowCategories cat ON c.CategoryId = cat.CategoryId
        WHERE cat.CategoryId IS NULL 
           OR cat.IsActive = 0 
           OR cat.RowType <> 'Detail'
    )
        THROW 50003, 'Only active Detail categories can be modified. Formula rows cannot be edited.', 1;

    -- Validate ValueType
    IF EXISTS (
        SELECT 1 FROM @Cells 
        WHERE ValueType NOT IN ('Actual', 'Projected')
    )
        THROW 50003, 'Invalid ValueType. Must be Actual or Projected.', 1;

    -- Validate Negative Values (Negative values not permitted for Detail lines)
    IF EXISTS (
        SELECT 1 FROM @Cells 
        WHERE NewAmount IS NOT NULL AND NewAmount < 0
    )
        THROW 50005, 'Negative amounts are not permitted for Cash Flow detail entries.', 1;

    -- -----------------------------------------------------------------
    -- 2. Atomic Transaction Execution
    -- -----------------------------------------------------------------
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Concurrency Check: Stale Existing Rows
        IF EXISTS (
            SELECT 1 
            FROM @Cells c
            INNER JOIN dbo.CashFlowDailyValues d WITH (UPDLOCK, HOLDLOCK)
                ON d.FinancialYearId = @FinancialYearId
               AND d.CategoryId = c.CategoryId
               AND d.EntryDate = c.EntryDate
               AND d.ValueType = c.ValueType
            WHERE c.RowVersion IS NULL 
               OR d.[RowVersion] <> c.RowVersion
        )
        BEGIN
            THROW 50001, 'Concurrency conflict: One or more records have been updated by another user since you loaded the statement.', 1;
        END

        -- Concurrency Check: Concurrent New Rows (RowVersion IS NULL but row was inserted concurrently)
        IF EXISTS (
            SELECT 1 
            FROM @Cells c
            INNER JOIN dbo.CashFlowDailyValues d WITH (UPDLOCK, HOLDLOCK)
                ON d.FinancialYearId = @FinancialYearId
               AND d.CategoryId = c.CategoryId
               AND d.EntryDate = c.EntryDate
               AND d.ValueType = c.ValueType
            WHERE c.RowVersion IS NULL
        )
        BEGIN
            THROW 50002, 'Concurrency conflict: A value for one or more cells was inserted by another user.', 1;
        END

        -- Identify genuinely changed cells vs identical submissions (no-op auditing filter)
        DECLARE @Diff TABLE
        (
            CategoryId INT           NOT NULL,
            EntryDate  DATE          NOT NULL,
            ValueType  VARCHAR(12)   NOT NULL,
            OldAmount  DECIMAL(19,4) NULL,
            NewAmount  DECIMAL(19,4) NULL,
            IsExisting BIT           NOT NULL,
            HasChanged BIT           NOT NULL
        );

        INSERT INTO @Diff (CategoryId, EntryDate, ValueType, OldAmount, NewAmount, IsExisting, HasChanged)
        SELECT 
            c.CategoryId,
            c.EntryDate,
            c.ValueType,
            d.Amount AS OldAmount,
            c.NewAmount,
            CASE WHEN d.CashFlowDailyValueId IS NOT NULL THEN 1 ELSE 0 END,
            CASE 
                WHEN d.Amount IS NULL AND c.NewAmount IS NULL THEN 0
                WHEN d.Amount IS NULL AND c.NewAmount IS NOT NULL THEN 1
                WHEN d.Amount IS NOT NULL AND c.NewAmount IS NULL THEN 1
                WHEN d.Amount <> c.NewAmount THEN 1
                ELSE 0
            END AS HasChanged
        FROM @Cells c
        LEFT JOIN dbo.CashFlowDailyValues d WITH (UPDLOCK, HOLDLOCK)
            ON d.FinancialYearId = @FinancialYearId
           AND d.CategoryId = c.CategoryId
           AND d.EntryDate = c.EntryDate
           AND d.ValueType = c.ValueType;

        -- 1. UPDATE existing changed rows
        UPDATE d
        SET 
            d.Amount = diff.NewAmount,
            d.UpdatedAt = SYSUTCDATETIME()
        FROM dbo.CashFlowDailyValues d
        INNER JOIN @Diff diff
            ON d.FinancialYearId = @FinancialYearId
           AND d.CategoryId = diff.CategoryId
           AND d.EntryDate = diff.EntryDate
           AND d.ValueType = diff.ValueType
        WHERE diff.IsExisting = 1 
          AND diff.HasChanged = 1;

        -- 2. INSERT new changed rows (skip inserting if new cell is NULL -> NULL)
        INSERT INTO dbo.CashFlowDailyValues
        (
            FinancialYearId,
            CategoryId,
            EntryDate,
            ValueType,
            Amount,
            CreatedAt,
            UpdatedAt
        )
        SELECT 
            @FinancialYearId,
            diff.CategoryId,
            diff.EntryDate,
            diff.ValueType,
            diff.NewAmount,
            SYSUTCDATETIME(),
            SYSUTCDATETIME()
        FROM @Diff diff
        WHERE diff.IsExisting = 0 
          AND diff.HasChanged = 1;

        -- 3. INSERT Audit entries strictly for rows that actually changed
        INSERT INTO dbo.CashFlowAuditLog
        (
            BatchId,
            FinancialYearId,
            CategoryId,
            EntryDate,
            ValueType,
            OldAmount,
            NewAmount,
            PrNumber,
            Remark,
            ModifiedByUserId,
            ModifiedByEmail,
            ModifiedAtUtc
        )
        SELECT 
            @BatchId,
            @FinancialYearId,
            CategoryId,
            EntryDate,
            ValueType,
            OldAmount,
            NewAmount,
            @PrNumber,
            @Remark,
            @ModifiedByUserId,
            @ModifiedByEmail,
            SYSUTCDATETIME()
        FROM @Diff
        WHERE HasChanged = 1;

        DECLARE @RowsModified INT;
        SELECT @RowsModified = COUNT(*) FROM @Diff WHERE HasChanged = 1;

        COMMIT TRANSACTION;

        -- Return modified count and batch ID
        SELECT 
            @RowsModified AS RowsModified, 
            @BatchId AS BatchId;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END
GO

-- ---------------------------------------------------------------------
-- 5. Stored Procedure: Read Audit History with User ID & Display Email
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_CashFlow_GetAuditHistory
    @FinancialYearId INT = 1,
    @PrNumber        NVARCHAR(100) = NULL,
    @FromDate        DATE = NULL,
    @ToDate          DATE = NULL,
    @CategoryId      INT = NULL,
    @ValueType       VARCHAR(12) = NULL,
    @PageNumber      INT = 1,
    @PageSize        INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @PageNumber < 1 SET @PageNumber = 1;
    IF @PageSize < 1 OR @PageSize > 200 SET @PageSize = 50;

    DECLARE @Offset INT = (@PageNumber - 1) * @PageSize;

    -- Validate dates
    IF @FromDate IS NOT NULL AND @ToDate IS NOT NULL AND @FromDate > @ToDate
        THROW 50003, 'FromDate cannot be after ToDate.', 1;

    -- Validate ValueType filter
    IF @ValueType IS NOT NULL AND @ValueType NOT IN ('Actual', 'Projected')
        THROW 50003, 'Invalid ValueType filter. Must be Actual or Projected.', 1;

    -- Result Set 1: Total Count
    SELECT COUNT(*) AS TotalCount
    FROM dbo.CashFlowAuditLog a
    WHERE a.FinancialYearId = @FinancialYearId
      AND (@PrNumber IS NULL OR a.PrNumber LIKE '%' + @PrNumber + '%')
      AND (@FromDate IS NULL OR a.EntryDate >= @FromDate)
      AND (@ToDate IS NULL OR a.EntryDate <= @ToDate)
      AND (@CategoryId IS NULL OR a.CategoryId = @CategoryId)
      AND (@ValueType IS NULL OR a.ValueType = @ValueType);

    -- Result Set 2: Paged Audit Entries
    SELECT 
        a.AuditLogId,
        a.BatchId,
        a.FinancialYearId,
        a.CategoryId,
        c.CategoryName,
        c.SectionName,
        a.EntryDate,
        a.ValueType,
        a.OldAmount,
        a.NewAmount,
        a.PrNumber,
        a.Remark,
        a.ModifiedByUserId,
        a.ModifiedByEmail,
        a.ModifiedAtUtc
    FROM dbo.CashFlowAuditLog a
    INNER JOIN dbo.CashFlowCategories c ON a.CategoryId = c.CategoryId
    WHERE a.FinancialYearId = @FinancialYearId
      AND (@PrNumber IS NULL OR a.PrNumber LIKE '%' + @PrNumber + '%')
      AND (@FromDate IS NULL OR a.EntryDate >= @FromDate)
      AND (@ToDate IS NULL OR a.EntryDate <= @ToDate)
      AND (@CategoryId IS NULL OR a.CategoryId = @CategoryId)
      AND (@ValueType IS NULL OR a.ValueType = @ValueType)
    ORDER BY a.ModifiedAtUtc DESC, a.AuditLogId DESC
    OFFSET @Offset ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO

-- ---------------------------------------------------------------------
-- 6. Update usp_CashFlow_GetStatementGrid to project RowVersion
-- ---------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_CashFlow_GetStatementGrid
    @FinancialYearId INT,
    @FromDate        DATE,
    @ToDate          DATE,
    @ValueType       VARCHAR(12) = 'Actual'
AS
BEGIN
    SET NOCOUNT ON;

    -- Detail rows with RowVersion projected as varbinary(8)
    SELECT
        c.CategoryId,
        c.CategoryName,
        c.SectionName,
        c.DisplayOrder,
        c.RowType,
        d.EntryDate,
        @ValueType AS ValueType,
        d.Amount,
        CAST(d.[RowVersion] AS VARBINARY(8)) AS [RowVersion]
    FROM dbo.CashFlowCategories c
    LEFT JOIN dbo.CashFlowDailyValues d
        ON  d.CategoryId       = c.CategoryId
        AND d.FinancialYearId  = @FinancialYearId
        AND d.ValueType        = @ValueType
        AND d.EntryDate       >= @FromDate
        AND d.EntryDate       <= @ToDate
    WHERE c.IsActive = 1
      AND c.RowType  = 'Detail'

    UNION ALL

    -- Dynamic Section Total for Inflow (Category 42)
    SELECT
        42,
        'Total Cash Inflow',
        'Inflow',
        999,
        'Total',
        d.EntryDate,
        @ValueType,
        SUM(d.Amount),
        NULL AS [RowVersion]
    FROM dbo.CashFlowDailyValues d
    INNER JOIN dbo.CashFlowCategories c
        ON  c.CategoryId = d.CategoryId
        AND c.SectionName = 'Inflow'
        AND c.IsActive    = 1
        AND c.RowType     = 'Detail'
    WHERE d.FinancialYearId = @FinancialYearId
      AND d.ValueType       = @ValueType
      AND d.EntryDate      >= @FromDate
      AND d.EntryDate      <= @ToDate
    GROUP BY d.EntryDate

    UNION ALL

    -- Dynamic Section Total for Outflow (Category 70)
    SELECT
        70,
        'Total Cash Outflow',
        'Outflow',
        999,
        'Total',
        d.EntryDate,
        @ValueType,
        SUM(d.Amount),
        NULL AS [RowVersion]
    FROM dbo.CashFlowDailyValues d
    INNER JOIN dbo.CashFlowCategories c
        ON  c.CategoryId = d.CategoryId
        AND c.SectionName = 'Outflow'
        AND c.IsActive    = 1
        AND c.RowType     = 'Detail'
    WHERE d.FinancialYearId = @FinancialYearId
      AND d.ValueType       = @ValueType
      AND d.EntryDate      >= @FromDate
      AND d.EntryDate      <= @ToDate
    GROUP BY d.EntryDate

    UNION ALL

    -- Non-Detail Categories (Subtotal, Total, Ratio in Borrowing or elsewhere)
    SELECT
        c.CategoryId,
        c.CategoryName,
        c.SectionName,
        c.DisplayOrder,
        c.RowType,
        d.EntryDate,
        @ValueType,
        d.Amount,
        CAST(d.[RowVersion] AS VARBINARY(8)) AS [RowVersion]
    FROM dbo.CashFlowCategories c
    LEFT JOIN dbo.CashFlowDailyValues d
        ON  d.CategoryId       = c.CategoryId
        AND d.FinancialYearId  = @FinancialYearId
        AND d.ValueType        = @ValueType
        AND d.EntryDate       >= @FromDate
        AND d.EntryDate       <= @ToDate
    WHERE c.IsActive = 1
      AND c.RowType <> 'Detail'
      AND c.CategoryId NOT IN (42, 70)

    ORDER BY SectionName, DisplayOrder, CategoryId, EntryDate;
END
GO
