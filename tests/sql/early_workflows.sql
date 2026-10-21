-- ONLY the dedicated disposable database created by build/test_early_workflows.sh.
-- These commands COMMIT. An outer ROLLBACK is not cleanup.
-- X'01'/X'02' etc are fictional opaque placeholders, NOT valid encryption.
USE micro_lending_workflow_test;

-- Two small test helpers: mismatches raise errors and stop the shell runner.
DELIMITER //
CREATE PROCEDURE test_assert(IN p_Condition BOOLEAN, IN p_Message VARCHAR(128))
BEGIN
    IF p_Condition IS NULL OR NOT p_Condition THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = p_Message;
    END IF;
    SET @passed = @passed + 1;
END //
CREATE PROCEDURE test_reject(IN p_SQL TEXT, IN p_ExpectedError INT)
BEGIN
    DECLARE v_Error INT DEFAULT 0;
    SET @test_statement = p_SQL;
    PREPARE test_statement FROM @test_statement;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN GET DIAGNOSTICS CONDITION 1 v_Error = MYSQL_ERRNO; END;
        EXECUTE test_statement;
    END;
    DEALLOCATE PREPARE test_statement;
    CALL test_assert(v_Error = p_ExpectedError, 'Expected rejection did not occur');
END //
CREATE TRIGGER test_force_audit_failure BEFORE INSERT ON AuditChange
FOR EACH ROW
BEGIN
    IF @force_audit_failure = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Forced audit failure';
    END IF;
END //
DELIMITER ;
SET @passed = 0;

-- Bootstrap only: one fictional Administrator so normal account operations can run.
INSERT INTO `User` (UserID, LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
VALUES (1, 'wf_admin', 'Test Administrator', 'wf_admin', X'01', 'constraint-test-only');
INSERT INTO UserRole (UserID, RoleCode) VALUES (1, 'Administrator');

CALL sp_create_user(1, 'wf_borrower', 'Borrower', 'wf_borrower', X'01', 'constraint-test-only');
SET @borrower = (SELECT UserID FROM `User` WHERE LoginName = 'wf_borrower');
CALL sp_create_user(1, 'wf_other', 'Other Borrower', 'wf_other', X'01', 'constraint-test-only');
SET @other = (SELECT UserID FROM `User` WHERE LoginName = 'wf_other');
CALL sp_create_user(1, 'wf_auditor', 'Auditor', 'wf_auditor', X'01', 'constraint-test-only');
SET @auditor = (SELECT UserID FROM `User` WHERE LoginName = 'wf_auditor');
CALL test_assert((SELECT AccountStatus = 'Active' AND RowVersion = 0 FROM `User` WHERE UserID = @borrower), 'New user defaults');
CALL test_reject('CALL sp_create_user(1, ''WF_BORROWER'', ''Duplicate'', ''other_alias'', X''01'', ''hash'')', 1062);
CALL test_reject('CALL sp_create_user(1, ''bad'', '' '', ''bad'', X''01'', ''hash'')', 1644);
CALL test_reject('CALL sp_create_user(@borrower, ''forbidden'', ''Bad'', ''bad'', X''01'', ''hash'')', 1644);
CALL sp_set_role(1, @borrower, 'Borrower', 1);
CALL sp_set_role(1, @borrower, 'Lender', 1);
CALL sp_set_role(1, @other, 'Borrower', 1);
CALL sp_set_role(1, @auditor, 'Auditor', 1);
CALL test_reject('CALL sp_set_role(1, @borrower, ''Borrower'', 1)', 1644);
CALL test_reject('CALL sp_set_role(1, @borrower, ''borrower'', 1)', 1644);
CALL test_reject('CALL sp_set_role(1, @borrower, ''Administrator'', 1)', 1644);
CALL test_reject('CALL sp_set_role(1, @auditor, ''Borrower'', 1)', 1644);
CALL test_reject('CALL sp_set_role(1, @auditor, ''Administrator'', 1)', 1644);
CALL test_reject('CALL sp_set_role(@borrower, @other, ''Lender'', 1)', 1644);
CALL sp_set_role(1, @borrower, 'Lender', 0);
CALL sp_set_role(1, @borrower, 'Lender', 1);
CALL test_assert((SELECT COUNT(*) = 2 FROM UserRole WHERE UserID = @borrower AND RoleCode = 'Lender'), 'Role episode history retained');
CALL test_assert((SELECT COUNT(*) = 1 FROM UserRole WHERE UserID = @borrower AND RoleCode = 'Lender' AND ActiveMarker = 1), 'One active role episode');

-- NULL means a new profile; updates must carry its current version.
CALL sp_save_profile(@borrower, NULL, '1000.00', '100.00', X'01', X'02');
CALL sp_save_profile(@other, NULL, '1000.00', '0', X'01', X'02');
CALL test_reject('CALL sp_save_profile(@borrower, 0, ''0'', ''0'', X''01'', X''02'')', 1644);
CALL test_reject('CALL sp_save_profile(@borrower, 0, ''1000'', ''-1'', X''01'', X''02'')', 1644);
CALL test_reject('CALL sp_save_profile(@borrower, 0, ''1000.001'', ''0'', X''01'', X''02'')', 1644);
CALL test_reject('CALL sp_save_profile(@borrower, 0, ''1000'', ''0'', X'''', X''02'')', 1644);
CALL test_reject('CALL sp_save_profile(@auditor, NULL, ''1000'', ''0'', X''01'', X''02'')', 1644);
CALL sp_save_profile(@borrower, 0, '1100', '100', X'03', X'04');
CALL test_reject('CALL sp_save_profile(@borrower, 0, ''1200'', ''100'', X''05'', X''06'')', 1644);
CALL test_assert((SELECT RowVersion = 1 AND MonthlyIncomeCipher = X'03' FROM BorrowerProfile WHERE UserID = @borrower), 'Profile update/version');

CALL sp_create_loan_request(@borrower, 'Original purpose', '600.00', 3);
SET @request = (SELECT MAX(RequestID) FROM LoanRequest WHERE BorrowerID = @borrower);
CALL test_reject('CALL sp_create_loan_request(@borrower, ''Fractional cents'', ''100.001'', 3)', 1644);
CALL test_reject('CALL sp_update_loan_request(@other, @request, 0, ''Stolen'', ''600'', 3)', 1644);
CALL test_reject('CALL sp_update_loan_request(@borrower, @request, 9, ''Stale'', ''600'', 3)', 1644);
CALL test_reject('CALL sp_update_loan_request(@borrower, @request, 0, '' '', ''600'', 3)', 1644);
CALL test_reject('CALL sp_update_loan_request(@borrower, @request, 0, ''Bad'', ''600.001'', 3)', 1644);
CALL test_reject('CALL sp_update_loan_request(@borrower, @request, 0, ''Bad'', ''99.99'', 3)', 1644);
CALL test_reject('CALL sp_update_loan_request(@borrower, @request, 0, ''Bad'', ''2000.01'', 3)', 1644);
CALL test_reject('CALL sp_update_loan_request(@borrower, @request, 0, ''Bad'', ''600'', 4)', 1644);
CALL sp_update_loan_request(@borrower, @request, 0, ' Updated purpose ', '600', 3);
CALL test_assert((SELECT Purpose = 'Updated purpose' AND RowVersion = 1 FROM LoanRequest WHERE RequestID = @request), 'Draft trimmed edit/version');

-- Restriction blocks new credit but still permits profile maintenance.
SET @version = (SELECT RowVersion FROM `User` WHERE UserID = @borrower);
CALL sp_set_account_status(1, @borrower, @version, 'Restricted', 'Demonstration restriction');
CALL sp_save_profile(@borrower, 1, '1000', '100', X'05', X'06');
CALL test_reject('CALL sp_create_loan_request(@borrower, ''Blocked'', ''600'', 3)', 1644);
CALL test_reject('CALL sp_update_loan_request(@borrower, @request, 1, ''Blocked'', ''600'', 3)', 1644);
CALL test_reject('CALL sp_prepare_submission(@borrower, @request, 1)', 1644);
CALL test_reject('CALL sp_set_account_status(1, @borrower, @version, ''Active'', ''stale'')', 1644);
SET @version = (SELECT RowVersion FROM `User` WHERE UserID = @borrower);
CALL test_reject('CALL sp_set_account_status(1, @borrower, @version, ''Active'', '' '')', 1644);
CALL test_reject('CALL sp_set_account_status(1, @borrower, @version, ''active'', ''bad case'')', 1644);
CALL sp_set_account_status(1, @borrower, @version, 'Active', 'Demonstration reactivation');

-- No preparation, wrong owner/version, or a lost transaction cannot submit.
CALL test_reject('CALL sp_submit_request(@borrower, @request, X''01'', ''1000'', ''100'', X''11'', X''12'', X''13'')', 1644);
CALL test_reject('CALL sp_prepare_submission(@other, @request, 1)', 1644);
CALL test_reject('CALL sp_prepare_submission(@borrower, @request, 0)', 1644);
CALL sp_prepare_submission(@borrower, @request, 1);
CALL test_assert(@ml_submit_burden = 0 AND @ml_submit_no_delinquency = 1, 'Initial exposure zero');
COMMIT;
CALL test_reject('CALL sp_submit_request(@borrower, @request, @ml_submit_context, ''1000'', ''100'', X''11'', X''12'', X''13'')', 1305);
CALL test_assert((SELECT RequestState = 'Draft' FROM LoanRequest WHERE RequestID = @request), 'Lost transaction leaves Draft');

-- Force an audit error after business writes. The SAME connection checks rollback.
SET @events = (SELECT COUNT(*) FROM AuditEvent);
SET @force_audit_failure = 1;
CALL test_reject('CALL sp_update_loan_request(@borrower, @request, 1, ''Rollback'', ''900'', 6)', 1644);
SET @force_audit_failure = 0;
CALL test_assert((SELECT Purpose = 'Updated purpose' AND RowVersion = 1 FROM LoanRequest WHERE RequestID = @request), 'Failed edit rolled back');
CALL test_assert((SELECT COUNT(*) = @events FROM AuditEvent), 'Failed edit audit rolled back');
CALL sp_prepare_submission(@borrower, @request, 1);
SET @force_audit_failure = 1;
CALL test_reject('CALL sp_submit_request(@borrower, @request, @ml_submit_context, ''1000'', ''100'', X''11'', X''12'', X''13'')', 1644);
SET @force_audit_failure = 0;
CALL test_assert((SELECT RequestState = 'Draft' AND RowVersion = 1 FROM LoanRequest WHERE RequestID = @request), 'Failed submission rolled back');
CALL test_assert((SELECT COUNT(*) = 0 FROM RequestEvaluation WHERE RequestID = @request), 'Failed submission evaluation rolled back');
CALL test_assert((SELECT COUNT(*) = @events FROM AuditEvent), 'Failed submission audit rolled back');
CALL test_assert(@ml_submit_context IS NULL, 'Failure clears submission context');

CALL sp_prepare_submission(@borrower, @request, 1);
CALL sp_submit_request(@borrower, @request, @ml_submit_context, '1000', '100', X'11', X'12', X'13');
CALL test_assert((SELECT RequestState = 'Submitted' AND PolicyCode = 'D1' AND RowVersion = 2
    AND SubmittedAt IS NOT NULL AND SubmittedIncomeCipher = X'11' FROM LoanRequest WHERE RequestID = @request), 'Submitted terms retained');
CALL test_assert((SELECT EvaluationKind = 'Submission' AND AttemptNumber = 0 AND AffordabilityPass IS NULL
    AND CompletedAt IS NULL AND Result IS NULL AND NoDelinquencyPass = 1
    FROM RequestEvaluation WHERE RequestID = @request), 'Snapshot is not completed assessment');
CALL test_reject('CALL sp_update_loan_request(@borrower, @request, 2, ''Changed'', ''700'', 3)', 1644);
CALL test_reject('CALL sp_prepare_submission(@borrower, @request, 2)', 1644);
CALL test_reject('UPDATE LoanRequest SET Principal = 700 WHERE RequestID = @request', 1644);
CALL test_reject('UPDATE LoanRequest SET SubmittedIncomeCipher = X''99'' WHERE RequestID = @request', 1644);
CALL test_reject('UPDATE LoanRequest SET RequestState = ''Draft'' WHERE RequestID = @request', 1644);
CALL sp_save_profile(@borrower, 2, '1500', '0', X'21', X'22');
CALL test_assert((SELECT SubmittedIncomeCipher = X'11' AND SubmittedObligationsCipher = X'12'
    FROM LoanRequest WHERE RequestID = @request), 'Later profile change does not alter snapshot');

CALL sp_create_loan_request(@borrower, 'Second request', '100', 6);
SET @second = (SELECT MAX(RequestID) FROM LoanRequest WHERE BorrowerID = @borrower);
CALL sp_prepare_submission(@borrower, @second, 0);
CALL test_assert(@ml_submit_burden = 200, 'Prior live request counted once');
CALL sp_submit_request(@borrower, @second, @ml_submit_context, '1500', '0', X'23', X'24', X'25');
SET @version = (SELECT RowVersion FROM `User` WHERE UserID = @borrower);
CALL test_reject('CALL sp_set_account_status(1, @borrower, @version, ''Inactive'', ''live obligations'')', 1644);
CALL test_reject('CALL sp_set_role(1, @borrower, ''Borrower'', 0)', 1644);
CALL test_reject('CALL sp_set_role(1, @borrower, ''Lender'', 0)', 1644);

-- Inactive users lose access on their next action; reactivation restores eligibility.
SET @version = (SELECT RowVersion FROM `User` WHERE UserID = @other);
CALL sp_set_account_status(1, @other, @version, 'Inactive', 'No live participation');
CALL test_reject('CALL sp_save_profile(@other, 0, ''1000'', ''0'', X''01'', X''02'')', 1644);
CALL test_reject('CALL sp_set_role(1, @other, ''Lender'', 1)', 1644);
SET @version = (SELECT RowVersion FROM `User` WHERE UserID = @other);
CALL sp_set_account_status(1, @other, @version, 'Active', 'Test reactivation');
CALL sp_set_role(1, @other, 'Borrower', 0);
CALL test_reject('CALL sp_save_profile(@other, 0, ''1000'', ''0'', X''01'', X''02'')', 1644);

CALL test_assert((SELECT COUNT(*) = 0 FROM AuditChange WHERE FieldName IN ('PrivateEmailCipher', 'PasswordHash',
    'MonthlyIncomeCipher', 'ExternalObligationsCipher', 'SubmittedIncomeCipher', 'SubmittedObligationsCipher')
    AND (OldValue IS NOT NULL OR NewValue IS NOT NULL)), 'Private audit values redacted');
CALL test_assert((SELECT COUNT(*) = 2 FROM AuditEvent WHERE EventType = 'RequestSubmitted'), 'Exactly two successful submissions');
-- Extra rejection/rollback coverage for all four account/profile writes.
SET @events = (SELECT COUNT(*) FROM AuditEvent);
SET @users = (SELECT COUNT(*) FROM `User`);
SET @version = (SELECT RowVersion FROM `User` WHERE UserID = @other);
SET @force_audit_failure = 1;
CALL test_reject('CALL sp_create_user(1, ''rollback_user'', ''Rollback'', ''rollback_alias'', X''01'', ''hash'')', 1644);
CALL test_reject('CALL sp_set_role(1, @other, ''Borrower'', 1)', 1644);
CALL test_reject('CALL sp_set_account_status(1, @other, @version, ''Restricted'', ''Rollback'')', 1644);
CALL test_reject('CALL sp_save_profile(@borrower, 3, ''2000'', ''0'', X''31'', X''32'')', 1644);
SET @force_audit_failure = 0;
CALL test_assert((SELECT COUNT(*) = @users FROM `User`), 'Failed user creation rolled back');
CALL test_assert((SELECT COUNT(*) = 0 FROM UserRole WHERE UserID = @other AND ActiveMarker = 1), 'Failed grant rolled back');
CALL test_assert((SELECT AccountStatus = 'Active' AND RowVersion = @version FROM `User` WHERE UserID = @other), 'Failed status rolled back');
CALL test_assert((SELECT RowVersion = 3 AND MonthlyIncomeCipher = X'21' FROM BorrowerProfile WHERE UserID = @borrower), 'Failed profile save rolled back');
CALL test_assert((SELECT COUNT(*) = @events FROM AuditEvent), 'No partial success audits');

-- Prepared context/envelope checks, including case-only edits of frozen terms.
CALL test_reject('UPDATE LoanRequest SET Purpose = LOWER(Purpose) WHERE RequestID = @request', 1644);
CALL sp_create_loan_request(@borrower, 'Prepare validation', '100', 3);
SET @third = (SELECT MAX(RequestID) FROM LoanRequest WHERE BorrowerID = @borrower);
CALL sp_prepare_submission(@borrower, @third, 0);
CALL test_reject('CALL sp_submit_request(@borrower, @third, UNHEX(REPEAT(''00'',16)), ''1000'', ''0'', X''11'', X''12'', X''13'')', 1644);
CALL sp_prepare_submission(@borrower, @third, 0);
CALL test_reject('CALL sp_submit_request(@borrower, @third, @ml_submit_context, ''1000.001'', ''0'', X''11'', X''12'', X''13'')', 1644);
CALL sp_prepare_submission(@borrower, @third, 0);
CALL test_reject('CALL sp_submit_request(@borrower, @third, @ml_submit_context, ''1000'', ''0'', X'''', X''12'', X''13'')', 1644);
CALL test_assert((SELECT RequestState = 'Draft' AND RowVersion = 0 FROM LoanRequest WHERE RequestID = @third), 'Rejected finishes leave Draft');

-- Structural fixture only: mimic a future activation so exposure is tested before
-- the funding workflow exists. Funded request is excluded, Active loan counted once.
UPDATE LoanRequest SET RequestState = 'Funded' WHERE RequestID = @request;
INSERT INTO Loan (RequestID, ActivatedAt, LastEvaluatedAt)
VALUES (@request, '2026-01-01 00:00:00', '2026-01-01 00:00:00');
SET @loan = LAST_INSERT_ID();
INSERT INTO Installment (LoanID, InstallmentNumber, DueDate, ScheduledPrincipal) VALUES
    (@loan, 1, '2026-02-01', 200), (@loan, 2, '2026-03-01', 200), (@loan, 3, '2026-04-01', 200);
START TRANSACTION;
CALL sp_submission_exposure(@borrower, @third, '2026-02-01', @burden, @clear);
CALL test_assert(@burden = 216.70 AND @clear = 1, 'Loan plus live request counted once; due today not overdue');
CALL sp_submission_exposure(@borrower, @third, '2026-02-02', @burden, @clear);
CALL test_assert(@burden = 216.70 AND @clear = 0, 'Delinquency derives from due date, not stored Current flag');
ROLLBACK;

-- A fictional applied commitment gives its lender outstanding participation too.
INSERT INTO OperationReceipt (CallerUserID, OperationReference, ActionCode)
VALUES (@other, 'fixture-applied', 'CommitFunding');
SET @op = LAST_INSERT_ID();
INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, PlatformBurdenCipher,
    NoDelinquencyPass, ContextID) VALUES (@request, 'Funding', 1, X'01', 1, UUID_TO_BIN(UUID()));
SET @evaluation = LAST_INSERT_ID();
INSERT INTO FundingCommitment (RequestID, OperationID, EvaluationID, Amount, CommitmentState, AppliedAt)
VALUES (@request, @op, @evaluation, 600, 'Applied', '2026-01-01');
SET @version = (SELECT RowVersion FROM `User` WHERE UserID = @other);
CALL test_reject('CALL sp_set_account_status(1, @other, @version, ''Inactive'', ''Participating lender'')', 1644);
START TRANSACTION;
CALL test_reject('CALL sp_require_no_live_participation(@other)', 1644);
ROLLBACK;

-- Pending commitments also prevent a lender from losing access to participation.
CALL sp_create_user(1, 'wf_pending_lender', 'Pending Lender', 'wf_pending_lender', X'01', 'test-only');
SET @pending_lender = (SELECT UserID FROM `User` WHERE LoginName = 'wf_pending_lender');
CALL sp_set_role(1, @pending_lender, 'Lender', 1);
INSERT INTO OperationReceipt (CallerUserID, OperationReference, ActionCode)
VALUES (@pending_lender, 'fixture-pending', 'CommitFunding');
SET @op = LAST_INSERT_ID();
INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, PlatformBurdenCipher,
    NoDelinquencyPass, ContextID) VALUES (@second, 'Funding', 1, X'01', 1, UUID_TO_BIN(UUID()));
SET @evaluation = LAST_INSERT_ID();
INSERT INTO FundingCommitment (RequestID, OperationID, EvaluationID, Amount)
VALUES (@second, @op, @evaluation, 50);
SET @version = (SELECT RowVersion FROM `User` WHERE UserID = @pending_lender);
CALL test_reject('CALL sp_set_account_status(1, @pending_lender, @version, ''Inactive'', ''Pending participation'')', 1644);
CALL test_reject('CALL sp_set_role(1, @pending_lender, ''Lender'', 0)', 1644);
CALL test_assert((SELECT AccountStatus = 'Active' AND RowVersion = @version FROM `User` WHERE UserID = @pending_lender), 'Pending participation preserves account');

SELECT @passed AS passed_checks;
SELECT RequestID, RequestState, RowVersion FROM LoanRequest ORDER BY RequestID;
