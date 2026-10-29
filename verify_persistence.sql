USE [CPCL_CashFlow_Local];
GO

PRINT '--- TEST 1: SAVE BATCH FOR CATEGORY 26 (Sales - Manali) ---';
DECLARE @tvp dbo.CashFlowCellSaveType;
INSERT INTO @tvp (CategoryId, EntryDate, ValueType, NewAmount, RowVersion)
VALUES (26, '2026-10-04', 'Actual', 155.75, NULL);

DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();

EXEC dbo.usp_CashFlow_SaveBatch 
    @FinancialYearId = 1,
    @PrNumber = 'PR-TEST-001',
    @Remark = 'Automated verification test',
    @ModifiedByUserId = 'test-admin-id',
    @ModifiedByEmail = 'admin@cpcl.co.in',
    @BatchId = @BatchId,
    @Cells = @tvp;

PRINT '--- VERIFY DAILY VALUES ---';
SELECT CategoryId, EntryDate, ValueType, Amount, CAST(RowVersion AS VARBINARY(8)) AS RowVersion
FROM dbo.CashFlowDailyValues
WHERE CategoryId = 26 AND EntryDate = '2026-10-04' AND ValueType = 'Actual';

PRINT '--- VERIFY AUDIT LOG ---';
SELECT AuditLogId, BatchId, CategoryId, EntryDate, ValueType, OldAmount, NewAmount, PrNumber, Remark, ModifiedByEmail, ModifiedAtUtc
FROM dbo.CashFlowAuditLog
WHERE PrNumber = 'PR-TEST-001';

PRINT '--- VERIFY GET AUDIT HISTORY PROCEDURE ---';
EXEC dbo.usp_CashFlow_GetAuditHistory 
    @FinancialYearId = 1, 
    @PrNumber = 'PR-TEST-001',
    @PageNumber = 1, 
    @PageSize = 10;
GO
