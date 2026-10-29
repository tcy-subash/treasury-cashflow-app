-- ==============================================================================
-- CPCL TREASURY MANAGEMENT SYSTEM - REVISED SEED SCRIPT (V2)
-- Database: CPCL_CashFlow_Local / CPCL_CashFlow_Test
-- Features:
-- 1. SET XACT_ABORT ON and TRY/CATCH with safe ROLLBACK and IDENTITY_INSERT reset
-- 2. Validates FinancialYearId = 1
-- 3. Non-destructive: Inserts missing rows only; does not overwrite existing amounts
-- 4. Reconciles exact 60 staged categories + 6 legacy = 66 total in database
-- ==============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    -- --------------------------------------------------------------------------
    -- 1. Verify FinancialYearId = 1
    -- --------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.CashFlowFinancialYears WHERE FinancialYearId = 1)
    BEGIN
        SET IDENTITY_INSERT dbo.CashFlowFinancialYears ON;
        INSERT INTO dbo.CashFlowFinancialYears (FinancialYearId, FinancialYearName, StartDate, EndDate)
        VALUES (1, N'2026-27', '2026-04-01', '2027-03-31');
        SET IDENTITY_INSERT dbo.CashFlowFinancialYears OFF;
    END
    ELSE
    BEGIN
        -- Verify existing dates match FY 2026-27 before updating
        DECLARE @CurStart DATE, @CurEnd DATE, @CurName NVARCHAR(50);
        SELECT @CurStart = StartDate, @CurEnd = EndDate, @CurName = FinancialYearName
        FROM dbo.CashFlowFinancialYears
        WHERE FinancialYearId = 1;

        IF @CurStart <> '2026-04-01' OR @CurEnd <> '2027-03-31'
        BEGIN
            THROW 51000, 'FinancialYearId = 1 has unexpected date boundaries. Aborting to prevent corrupting financial periods.', 1;
        END;

        IF @CurName <> N'2026-27'
        BEGIN
            UPDATE dbo.CashFlowFinancialYears
            SET FinancialYearName = N'2026-27'
            WHERE FinancialYearId = 1;
        END;
    END;

    -- --------------------------------------------------------------------------
    -- 2. Stage verified 60 categories derived from Excel CASH FLOW sheet
    -- --------------------------------------------------------------------------
    CREATE TABLE #CategoriesStage (
        CategoryId INT NOT NULL PRIMARY KEY,
        CategoryName NVARCHAR(255) NOT NULL,
        SectionName NVARCHAR(50) NOT NULL,
        DisplayOrder INT NOT NULL,
        RowType NVARCHAR(30) NOT NULL,
        IsActive BIT NOT NULL
    );

    INSERT INTO #CategoriesStage (CategoryId, CategoryName, SectionName, DisplayOrder, RowType, IsActive)
    VALUES
    -- INFLOW SECTION (17 categories)
    (26, N'Sales - Manali',                      N'Inflow',     5, N'Detail',   1),
    (27, N'Other Receipts',                      N'Inflow',    10, N'Detail',   1),
    (28, N'Sales - Terminal & Other OMCs',       N'Inflow',    20, N'Detail',   1),
    (29, N'Excise Duty',                         N'Inflow',    30, N'Detail',   1),
    (30, N'Sales Tax / GST',                     N'Inflow',    40, N'Detail',   1),
    (31, N'Short Term Loan - SBI',               N'Inflow',    50, N'Detail',   1),
    (32, N'Short Term Loan - CC as WCL',         N'Inflow',    60, N'Detail',   1),
    (33, N'Short Term Loan - Others',             N'Inflow',    70, N'Detail',   1),
    (34, N'Short Term FC - SBI',                 N'Inflow',    80, N'Detail',   1),
    (35, N'Short Term FC - Others',              N'Inflow',    90, N'Detail',   1),
    (36, N'Commercial Paper',                    N'Inflow',   100, N'Detail',   1),
    (37, N'Commercial Paper - SBI',              N'Inflow',   110, N'Detail',   1),
    (38, N'Long Term - Rupee',                   N'Inflow',   120, N'Detail',   1),
    (39, N'Long Term - FC',                      N'Inflow',   130, N'Detail',   1),
    (40, N'Investment Maturity - Income',        N'Inflow',   140, N'Detail',   1),
    (41, N'Investment Maturity - Principal',     N'Inflow',   150, N'Detail',   1),
    (42, N'Total Cash Inflow',                   N'Inflow',   999, N'Total',    1),

    -- OUTFLOW SECTION (25 categories)
    (46, N'Crude - IOC',                         N'Outflow',   10, N'Detail',   1),
    (47, N'Crude - ONGC / Others',               N'Outflow',   20, N'Detail',   1),
    (48, N'Crude - CBR',                         N'Outflow',   30, N'Detail',   1),
    (49, N'Cust. Duty / Wharfage / Freight',     N'Outflow',   40, N'Detail',   1),
    (50, N'Excise Duty',                         N'Outflow',   45, N'Detail',   1),
    (51, N'Sales Tax / GST (Incl TDS)',          N'Outflow',   50, N'Detail',   1),
    (52, N'Project - Plan & Non Plan',           N'Outflow',   60, N'Detail',   1),
    (53, N'Long Term Rupee Loans Repay',         N'Outflow',   70, N'Detail',   1),
    (54, N'Long Term FC Loans Repay',            N'Outflow',   80, N'Detail',   1),
    (55, N'Interest - OIDB / Other LT Loans',    N'Outflow',   90, N'Detail',   1),
    (56, N'Short Term Loan - SBI Repay',         N'Outflow',  100, N'Detail',   1),
    (57, N'Short Term Loan - Others Repay',       N'Outflow',  110, N'Detail',   1),
    (58, N'Short Term Loan - Prepayment',        N'Outflow',  120, N'Detail',   1),
    (59, N'Commercial Paper Repay',              N'Outflow',  130, N'Detail',   1),
    (60, N'Commercial Paper Repay - SBI',        N'Outflow',  140, N'Detail',   1),
    (61, N'Foreign Currency Loan Repay - SBI',   N'Outflow',  150, N'Detail',   1),
    (62, N'Foreign Currency Loan Repay - Others',N'Outflow',  160, N'Detail',   1),
    (63, N'Income Tax',                          N'Outflow',  170, N'Detail',   1),
    (64, N'Payroll & Off Cycle',                 N'Outflow',  180, N'Detail',   1),
    (65, N'Pur.Cont.Misc',                       N'Outflow',  190, N'Detail',   1),
    (66, N'Investments',                         N'Outflow',  200, N'Detail',   1),
    (67, N'Interest',                            N'Outflow',  205, N'Detail',   1),
    (68, N'Dividend - Equity',                   N'Outflow',  210, N'Detail',   1),
    (69, N'Dividend - Preference',               N'Outflow',  220, N'Detail',   1),
    (70, N'Total Cash Outflow',                  N'Outflow',  999, N'Total',    1),

    -- BORROWING & UTILIZATION SECTION (18 categories)
    (72, N'Cash Credit - SBI',                   N'Borrowing', 10, N'Detail',   1),
    (73, N'Short Term Re Loans - SBI',           N'Borrowing', 20, N'Detail',   1),
    (74, N'Commercial Paper - SBI',              N'Borrowing', 30, N'Detail',   1),
    (75, N'Total SBI Utilization',               N'Borrowing', 40, N'Subtotal', 1),
    (76, N'Short Term Re Loans - Others',        N'Borrowing', 50, N'Detail',   1),
    (77, N'Commercial Paper - Others',           N'Borrowing', 60, N'Detail',   1),
    (78, N'Total Rupee Others',                  N'Borrowing', 70, N'Subtotal', 1),
    (79, N'Total Commercial Paper Limit Utilized', N'Borrowing', 80, N'Subtotal', 1),
    (80, N'Total Short Term Rupee Borrowings',   N'Borrowing', 90, N'Subtotal', 1),
    (81, N'Short Term FC - SBI',                 N'Borrowing', 100, N'Detail',  1),
    (82, N'Short Term FC - Others',              N'Borrowing', 110, N'Detail',  1),
    (83, N'Total Short Term FC Borrowings',      N'Borrowing', 120, N'Subtotal', 1),
    (84, N'Total Short Term Borrowings',         N'Borrowing', 130, N'Subtotal', 1),
    (85, N'Long Term Rupee Borrowings',          N'Borrowing', 140, N'Detail',  1),
    (86, N'Long Term FC Borrowings',             N'Borrowing', 150, N'Detail',  1),
    (87, N'Total Long Term Borrowings',          N'Borrowing', 160, N'Subtotal', 1),
    (88, N'Total Borrowings (Gross)',            N'Borrowing', 990, N'Total',   1),
    (89, N'Borrowings to Net Worth Ratio',       N'Borrowing', 995, N'Ratio',   1);

    -- Soft-deactivate legacy dummy categories (1 to 6) without deleting them
    UPDATE dbo.CashFlowCategories
    SET IsActive = 0
    WHERE CategoryId BETWEEN 1 AND 6;

    -- Insert newly added categories safely
    SET IDENTITY_INSERT dbo.CashFlowCategories ON;

    INSERT INTO dbo.CashFlowCategories (CategoryId, CategoryName, SectionName, DisplayOrder, RowType, IsActive)
    SELECT s.CategoryId, s.CategoryName, s.SectionName, s.DisplayOrder, s.RowType, s.IsActive
    FROM #CategoriesStage s
    LEFT JOIN dbo.CashFlowCategories c ON c.CategoryId = s.CategoryId
    WHERE c.CategoryId IS NULL;

    SET IDENTITY_INSERT dbo.CashFlowCategories OFF;

    -- Update metadata (Name, Section, Order, Type) for staged categories without touching transactions
    UPDATE c
    SET c.CategoryName = s.CategoryName,
        c.SectionName = s.SectionName,
        c.DisplayOrder = s.DisplayOrder,
        c.RowType = s.RowType,
        c.IsActive = s.IsActive
    FROM dbo.CashFlowCategories c
    INNER JOIN #CategoriesStage s ON c.CategoryId = s.CategoryId;

    DROP TABLE #CategoriesStage;

    -- --------------------------------------------------------------------------
    -- 3. Seed Verified FY 2026-27 Opening Balance
    --    Only insert if missing; do not overwrite non-zero existing balance
    -- --------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.CashFlowOpeningBalances WHERE FinancialYearId = 1 AND ValueType = 'Actual')
    BEGIN
        INSERT INTO dbo.CashFlowOpeningBalances (FinancialYearId, ValueType, OpeningBalance)
        VALUES (1, 'Actual', 33.5510);
    END
    ELSE
    BEGIN
        UPDATE dbo.CashFlowOpeningBalances
        SET OpeningBalance = 33.5510
        WHERE FinancialYearId = 1 AND ValueType = 'Actual' AND OpeningBalance = 0;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.CashFlowOpeningBalances WHERE FinancialYearId = 1 AND ValueType = 'Projected')
    BEGIN
        INSERT INTO dbo.CashFlowOpeningBalances (FinancialYearId, ValueType, OpeningBalance)
        VALUES (1, 'Projected', 33.5510);
    END
    ELSE
    BEGIN
        UPDATE dbo.CashFlowOpeningBalances
        SET OpeningBalance = 33.5510
        WHERE FinancialYearId = 1 AND ValueType = 'Projected' AND OpeningBalance = 0;
    END;

    -- --------------------------------------------------------------------------
    -- 4. Ingest Verified Sample Values for 2026-04-01 & 2026-04-02
    --    INSERT ONLY (WHERE NOT EXISTS) to never overwrite existing financial records
    -- --------------------------------------------------------------------------
    CREATE TABLE #DailyValuesStage (
        FinancialYearId INT NOT NULL,
        CategoryId INT NOT NULL,
        EntryDate DATE NOT NULL,
        ValueType VARCHAR(12) NOT NULL,
        Amount DECIMAL(19,4) NOT NULL
    );

    -- Col E (2026-04-01 - Bank Holiday)
    INSERT INTO #DailyValuesStage VALUES (1, 26, '2026-04-01', 'Actual', 3.4100); -- Sales - Manali
    INSERT INTO #DailyValuesStage VALUES (1, 57, '2026-04-01', 'Actual', 2.0000); -- ST Loan - Others Repay

    -- Col F (2026-04-02 - Working Day)
    INSERT INTO #DailyValuesStage VALUES (1, 26, '2026-04-02', 'Actual', 8.3400);   -- Sales - Manali
    INSERT INTO #DailyValuesStage VALUES (1, 28, '2026-04-02', 'Actual', 2593.4000); -- Sales - Terminal & Other OMCs
    INSERT INTO #DailyValuesStage VALUES (1, 31, '2026-04-02', 'Actual', 1952.0000); -- ST Loan - SBI
    INSERT INTO #DailyValuesStage VALUES (1, 33, '2026-04-02', 'Actual', 615.9500);  -- ST Loan - Others

    INSERT INTO #DailyValuesStage VALUES (1, 46, '2026-04-02', 'Actual', 4860.9200); -- Crude - IOC
    INSERT INTO #DailyValuesStage VALUES (1, 48, '2026-04-02', 'Actual', 24.2500);   -- Crude - CBR
    INSERT INTO #DailyValuesStage VALUES (1, 49, '2026-04-02', 'Actual', 1.3300);    -- Cust. Duty / Wharfage / Freight
    INSERT INTO #DailyValuesStage VALUES (1, 57, '2026-04-02', 'Actual', 268.9700);  -- ST Loan - Others Repay
    INSERT INTO #DailyValuesStage VALUES (1, 64, '2026-04-02', 'Actual', 12.3500);   -- Payroll & Off Cycle
    INSERT INTO #DailyValuesStage VALUES (1, 65, '2026-04-02', 'Actual', 2.7300);    -- Pur.Cont.Misc
    INSERT INTO #DailyValuesStage VALUES (1, 66, '2026-04-02', 'Actual', 33.3800);   -- Investments
    INSERT INTO #DailyValuesStage VALUES (1, 67, '2026-04-02', 'Actual', 0.1100);    -- Interest

    -- Borrowing Positions
    INSERT INTO #DailyValuesStage VALUES (1, 73, '2026-04-02', 'Actual', 1952.0013);
    INSERT INTO #DailyValuesStage VALUES (1, 76, '2026-04-02', 'Actual', 1954.9482);
    INSERT INTO #DailyValuesStage VALUES (1, 85, '2026-04-02', 'Actual', 764.3720);

    -- Projected mirror
    INSERT INTO #DailyValuesStage
    SELECT FinancialYearId, CategoryId, EntryDate, 'Projected', Amount
    FROM #DailyValuesStage;

    -- Non-destructive INSERT: only inserts if record does not exist
    INSERT INTO dbo.CashFlowDailyValues (FinancialYearId, CategoryId, EntryDate, ValueType, Amount, CreatedAt)
    SELECT s.FinancialYearId, s.CategoryId, s.EntryDate, s.ValueType, s.Amount, GETDATE()
    FROM #DailyValuesStage s
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.CashFlowDailyValues v
        WHERE v.FinancialYearId = s.FinancialYearId
          AND v.CategoryId = s.CategoryId
          AND v.EntryDate = s.EntryDate
          AND v.ValueType = s.ValueType
    );

    DROP TABLE #DailyValuesStage;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    -- Ensure IDENTITY_INSERT is disabled if it failed mid-flight
    IF OBJECTPROPERTY(OBJECT_ID('dbo.CashFlowCategories'), 'TableHasIdentity') = 1
    BEGIN
        SET IDENTITY_INSERT dbo.CashFlowCategories OFF;
    END;

    IF OBJECTPROPERTY(OBJECT_ID('dbo.CashFlowFinancialYears'), 'TableHasIdentity') = 1
    BEGIN
        SET IDENTITY_INSERT dbo.CashFlowFinancialYears OFF;
    END;

    THROW;
END CATCH;
GO
