-- Presentation and automatic checks, ONLY after the fictional midterm seed.
-- Run through build/demo_midterm.sh or select the dedicated demo DB in Workbench.
-- Public actions COMMIT. No development database is selected or cleared here.
CREATE TEMPORARY TABLE midterm_demo_guard (Safe TINYINT NOT NULL CHECK (Safe = 1));
INSERT INTO midterm_demo_guard SELECT DATABASE() IN ('micro_lending_midterm_demo', 'micro_lending_midterm_test');
DROP TEMPORARY TABLE midterm_demo_guard;
SET SESSION time_zone = '+00:00';
SET @midterm_checks = 0;
DELIMITER //
CREATE PROCEDURE midterm_assert(IN p_Ok BOOLEAN, IN p_Message VARCHAR(128))
BEGIN
    IF p_Ok IS NULL OR NOT p_Ok THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = p_Message; END IF;
    SET @midterm_checks = @midterm_checks + 1;
END //
CREATE PROCEDURE midterm_reject(IN p_SQL TEXT, IN p_Error INT, IN p_Label VARCHAR(128))
BEGIN
    DECLARE v_Error INT DEFAULT 0;
    SET @midterm_sql = p_SQL;
    PREPARE midterm_statement FROM @midterm_sql;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN GET DIAGNOSTICS CONDITION 1 v_Error = MYSQL_ERRNO; END;
        EXECUTE midterm_statement;
    END;
    DEALLOCATE PREPARE midterm_statement;
    CALL midterm_assert(v_Error = p_Error, p_Label);
END //
-- Test-only injection: fail AFTER the request update and AuditEvent insert.
CREATE TRIGGER midterm_force_audit_failure BEFORE INSERT ON AuditChange
FOR EACH ROW
BEGIN
    IF @midterm_fail_audit = 1 AND NEW.FieldName = 'TerminalReason' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Midterm forced audit failure';
    END IF;
END //
DELIMITER ;

SELECT '1. CREATE and READ: a new owned Draft, version 0' AS DemoStep;
CALL sp_create_loan_request(1, 'Midterm fictional equipment', '300.00', 3);
SET @request = (SELECT MAX(RequestID) FROM LoanRequest WHERE BorrowerID = 1);
SELECT * FROM v_borrower_requests WHERE RequestID = @request;
CALL midterm_assert((SELECT RequestState = 'Draft' AND RowVersion = 0 FROM LoanRequest WHERE RequestID = @request), 'Draft creation');

SELECT '2. EDIT: expected version 0 becomes version 1' AS DemoStep;
CALL sp_update_loan_request(1, @request, 0, 'Midterm revised equipment', '600.00', 6);
CALL midterm_assert((SELECT Principal = 600 AND InstallmentCount = 6 AND RowVersion = 1 FROM LoanRequest WHERE RequestID = @request), 'Draft editing');

SELECT '3. CANCEL is UPDATE: keep the row, reason and terms; version becomes 2' AS DemoStep;
CALL sp_cancel_draft(1, 'Borrower', @request, 1, '  No longer needed for this fictional example.  ');
SELECT RequestID, BorrowerID, RequestState, Principal, InstallmentCount, TerminalReason, RowVersion
FROM LoanRequest WHERE RequestID = @request;
CALL midterm_assert((SELECT RequestState = 'Cancelled' AND RowVersion = 2
    AND BorrowerID = 1 AND Purpose = 'Midterm revised equipment' AND Principal = 600 AND InstallmentCount = 6
    AND TerminalReason = 'No longer needed for this fictional example.'
    AND SubmittedAt IS NULL AND PolicyCode IS NULL FROM LoanRequest WHERE RequestID = @request), 'Cancellation retains row and terms');
SET @cancel_event = (SELECT MAX(AuditEventID) FROM AuditEvent WHERE EventType = 'RequestCancelled' AND SubjectKey = CAST(@request AS CHAR));
CALL midterm_assert((SELECT ActorUserID = 1 AND ActingRoleCode = 'Borrower' AND ReasonCode = 'BORROWER_CANCELLED'
    AND TechnicalAccount = SESSION_USER() FROM AuditEvent WHERE AuditEventID = @cancel_event), 'Owner cancellation attribution');
CALL midterm_assert((SELECT COUNT(*) = 2 FROM AuditChange WHERE AuditEventID = @cancel_event), 'Two cancellation change rows');

SELECT '4. REJECTED ACTIONS: terminal edit, repeated cancellation and hard deletion' AS DemoStep;
CALL midterm_reject('CALL sp_update_loan_request(1, @request, 2, ''Cannot edit'', ''300'', 3)', 1644, 'Cancelled request cannot be edited');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', @request, 2, ''Again'')', 1644, 'Repeated cancellation rejected');
CALL midterm_reject('DELETE FROM LoanRequest WHERE RequestID = @request', 1644, 'Hard deletion rejected');
CALL midterm_assert((SELECT COUNT(*) = 1 FROM LoanRequest WHERE RequestID = @request), 'Rejected delete retained row');

SELECT '5. FORCED ROLLBACK: audit failure undoes the cancellation and all its audit rows' AS DemoStep;
CALL sp_create_loan_request(1, 'Midterm rollback example', '300', 3);
SET @rollback_request = (SELECT MAX(RequestID) FROM LoanRequest WHERE BorrowerID = 1);
SET @audit_before = (SELECT COUNT(*) FROM AuditEvent);
SET @changes_before = (SELECT COUNT(*) FROM AuditChange);
SET @midterm_fail_audit = 1;
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', @rollback_request, 0, ''Force failure'')', 1644, 'Injected audit failure returned');
SET @midterm_fail_audit = 0;
CALL midterm_assert((SELECT RequestState = 'Draft' AND RowVersion = 0 AND TerminalReason IS NULL FROM LoanRequest WHERE RequestID = @rollback_request), 'Rollback restores Draft version and reason');
CALL midterm_assert((SELECT COUNT(*) = @audit_before FROM AuditEvent), 'Rollback removes new audit event');
CALL midterm_assert((SELECT COUNT(*) = @changes_before FROM AuditChange), 'Rollback removes partial audit changes');
SELECT RequestID, RequestState, RowVersion, TerminalReason FROM LoanRequest WHERE RequestID = @rollback_request;

-- Additional cancellation boundaries; these are still request-management tests.
CALL midterm_reject('CALL sp_cancel_draft(4, ''Borrower'', @rollback_request, 0, ''Wrong owner'')', 1644, 'Non-owner denied');
CALL midterm_reject('CALL sp_cancel_draft(2, ''Lender'', @rollback_request, 0, ''Wrong role'')', 1644, 'Lender role denied');
CALL midterm_reject('CALL sp_cancel_draft(2, ''Administrator'', @rollback_request, 0, ''Claimed role'')', 1644, 'Claimed Administrator without grant denied');
CALL midterm_reject('CALL sp_cancel_draft(1, ''borrower'', @rollback_request, 0, ''Wrong capitalization'')', 1644, 'Noncanonical role denied');
CALL midterm_reject('CALL sp_cancel_draft(NULL, ''Borrower'', @rollback_request, 0, ''Missing actor'')', 1644, 'Missing actor denied');
CALL midterm_reject('CALL sp_cancel_draft(1, NULL, @rollback_request, 0, ''Missing role'')', 1644, 'Missing role denied');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', NULL, 0, ''Missing target'')', 1644, 'Missing request denied');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', 999999999, 0, ''Unknown target'')', 1644, 'Unknown request denied');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', @rollback_request, NULL, ''Missing version'')', 1644, 'Missing version denied');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', @rollback_request, 1, ''Stale version'')', 1644, 'Stale version denied');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', @rollback_request, 0, NULL)', 1644, 'Missing reason denied');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', @rollback_request, 0, ''   '')', 1644, 'Blank reason denied');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', @rollback_request, 0, CHAR(9,10))', 1644, 'Whitespace-only reason denied');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', @rollback_request, 0, REPEAT(''x'',1001))', 1644, 'Oversize reason denied');
CALL midterm_reject('CALL sp_cancel_draft(4, ''Borrower'', 103, 0, ''Not a Draft'')', 1644, 'OpenFunding cancellation deferred');
CALL midterm_reject('CALL sp_cancel_draft(1, ''Borrower'', 101, 4, ''Funded'')', 1644, 'Funded request cancellation denied');
-- Even an UNREFERENCED Draft cannot be hard-deleted; this is not just an FK error.
CALL midterm_reject('DELETE FROM LoanRequest WHERE RequestID = @rollback_request', 1644, 'Unreferenced Draft deletion denied');
CALL midterm_reject('DELETE FROM LoanRequest WHERE RequestID = 101', 1644, 'Referenced request deletion denied before FK check');
CALL midterm_assert((SELECT RequestState = 'Draft' AND RowVersion = 0 FROM LoanRequest WHERE RequestID = @rollback_request), 'All rejected actions leave Draft unchanged');
CALL midterm_assert((SELECT COUNT(*) = @audit_before FROM AuditEvent), 'Rejected actions do not invent success audits');

-- Restricted owners may still cancel, without permitting new borrowing.
SET @account_version = (SELECT RowVersion FROM `User` WHERE UserID = 1);
CALL sp_set_account_status(5, 1, @account_version, 'Restricted', 'Fictional midterm restriction');
CALL sp_cancel_draft(1, 'Borrower', @rollback_request, 0, REPEAT('x', 1000));
CALL midterm_assert((SELECT RequestState = 'Cancelled' AND CHAR_LENGTH(TerminalReason) = 1000 FROM LoanRequest WHERE RequestID = @rollback_request), 'Restricted owner and maximum reason allowed');
CALL sp_set_account_status(5, 1, @account_version + 1, 'Active', 'Fictional restriction cleared');

-- The inactive/revoked-role case uses a new fictional account with no live loans.
CALL sp_create_user(5, CONCAT('midterm_', @request), 'Midterm inactive-role example', CONCAT('midterm_', @request), X'01', 'fixture-not-a-login');
SET @inactive = (SELECT UserID FROM `User` WHERE LoginName = CONCAT('midterm_', @request));
CALL sp_set_role(5, @inactive, 'Borrower', 1);
CALL sp_save_profile(@inactive, NULL, '1000', '0', X'01', X'02');
CALL sp_create_loan_request(@inactive, 'Midterm admin cancellation', '300', 3);
SET @admin_request = (SELECT MAX(RequestID) FROM LoanRequest WHERE BorrowerID = @inactive);
SET @inactive_version = (SELECT RowVersion FROM `User` WHERE UserID = @inactive);
CALL sp_set_account_status(5, @inactive, @inactive_version, 'Inactive', 'Fictional inactive account');
CALL midterm_reject('CALL sp_cancel_draft(@inactive, ''Borrower'', @admin_request, 0, ''Inactive'')', 1644, 'Inactive owner denied');
CALL sp_set_account_status(5, @inactive, @inactive_version + 1, 'Active', 'Fictional reactivation');
CALL sp_set_role(5, @inactive, 'Borrower', 0);
CALL midterm_reject('CALL sp_cancel_draft(@inactive, ''Borrower'', @admin_request, 0, ''Revoked'')', 1644, 'Revoked Borrower role denied');
CALL sp_cancel_draft(5, 'Administrator', @admin_request, 0, 'Administrator cancelled this fictional Draft.');
CALL midterm_assert((SELECT COUNT(*) = 1 FROM AuditEvent WHERE EventType = 'RequestCancelled' AND SubjectKey = CAST(@admin_request AS CHAR)
    AND ActorUserID = 5 AND ActingRoleCode = 'Administrator' AND ReasonCode = 'ADMIN_DECISION'), 'Administrator cancellation attribution');

SELECT '6. REPORTS: seeded finance is historical data, not implemented workflows' AS DemoStep;
SELECT * FROM v_borrower_requests WHERE BorrowerID = 1 ORDER BY RequestID;
SELECT * FROM v_request_funding_progress WHERE RequestState IN ('OpenFunding', 'Funded') ORDER BY RequestID;
SELECT * FROM v_loan_balances ORDER BY LoanID;
CALL midterm_assert((SELECT COUNT(*) = 1 AND MAX(AppliedPrincipal) = 900 AND MAX(RemainingToFund) = 0 FROM v_request_funding_progress WHERE RequestID = 101), 'Repeated contributions aggregate once per request');
CALL midterm_assert((SELECT PendingPrincipal = 100 AND RemainingToFund = 200 FROM v_request_funding_progress WHERE RequestID = 103), 'Partly funded request progress');
CALL midterm_assert((SELECT OutstandingPrincipal = 550 AND AllocatedPrincipal = 350 FROM v_loan_balances WHERE LoanID = 501), 'Seeded loan 501 balances');
CALL midterm_assert((SELECT OutstandingPrincipal = 200 AND AllocatedPrincipal = 400 FROM v_loan_balances WHERE LoanID = 502), 'Seeded loan 502 balances');
CALL midterm_assert((SELECT SUM(OutstandingPrincipal) = 750 FROM v_loan_balances WHERE BorrowerID = 1), 'Borrower balance across two loans');
-- EXISTS avoids multiplying a loan when its lender contributed twice.
SELECT b.LoanID, b.OutstandingPrincipal FROM v_loan_balances b
WHERE EXISTS (SELECT 1 FROM FundingCommitment c JOIN OperationReceipt o ON o.OperationID = c.OperationID
    WHERE c.RequestID = b.RequestID AND c.CommitmentState = 'Applied' AND o.CallerUserID = 2);
CALL midterm_assert((SELECT SUM(b.OutstandingPrincipal) = 550 FROM v_loan_balances b
    WHERE EXISTS (SELECT 1 FROM FundingCommitment c JOIN OperationReceipt o ON o.OperationID = c.OperationID
        WHERE c.RequestID = b.RequestID AND c.CommitmentState = 'Applied' AND o.CallerUserID = 2)), 'Repeated lender contributions do not multiply balance');
-- Explicit historical report date: an installment due on that date is NOT overdue.
SET @report_date = DATE('2026-10-19');
SELECT @report_date AS ReportDate, LoanID, InstallmentNumber, DueDate, RemainingPrincipal,
    DATEDIFF(@report_date, DueDate) AS DaysPastDue
FROM v_installment_remaining WHERE DueDate < @report_date AND RemainingPrincipal > 0 ORDER BY LoanID, DueDate;
CALL midterm_assert((SELECT SUM(RemainingPrincipal) = 250 FROM v_installment_remaining WHERE LoanID = 501 AND DueDate < @report_date), 'Historical overdue amount');

SELECT '7. AUDIT and EXPLAIN: history joins; primary-key lookup' AS DemoStep;
SELECT e.AuditEventID, e.EventType, e.ActorUserID, e.ActingRoleCode, e.ReasonCode,
    c.FieldName, c.OldValue, c.NewValue
FROM AuditEvent e JOIN AuditChange c ON c.AuditEventID = e.AuditEventID
WHERE e.SubjectType = 'LoanRequest' AND e.SubjectKey = CAST(@request AS CHAR)
ORDER BY e.OccurredAt, e.AuditEventID, c.FieldName;
EXPLAIN SELECT RequestID, RequestState, RowVersion FROM LoanRequest WHERE RequestID = @request;
SELECT @midterm_checks AS PassedMidtermChecks;
DROP TRIGGER midterm_force_audit_failure;
DROP PROCEDURE midterm_reject;
DROP PROCEDURE midterm_assert;
