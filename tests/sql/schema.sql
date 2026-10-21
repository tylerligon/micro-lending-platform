-- Full-schema structural walkthrough. Run after schema.sql and the four-role seed.
-- These fictional rows demonstrate keys/checks, not an executed application workflow.
-- X'01'/X'02' are dummy bytes, not encrypted amounts or valid response snapshots.
-- Never COMMIT this file. The final ROLLBACK removes every demonstration row.
-- Names beginning schema_demo_ are reserved; stop on any setup error.

-- SECTION 1: Create the related rows in dependency order.
SET SESSION time_zone = '+00:00';
START TRANSACTION;
SET @example_time = '2026-10-20 12:00:00';
SET @example_context = X'00112233445566778899aabbccddeeff';

INSERT INTO `User` (LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
VALUES ('schema_demo_borrower', 'Schema Borrower', 'schema_demo_borrower', X'01', 'constraint-test-only');
SET @example_borrower = LAST_INSERT_ID();
INSERT INTO `User` (LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
VALUES ('schema_demo_lender', 'Schema Lender', 'schema_demo_lender', X'01', 'constraint-test-only');
SET @example_lender = LAST_INSERT_ID();
INSERT INTO `User` (LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
VALUES ('schema_demo_admin', 'Schema Administrator', 'schema_demo_admin', X'01', 'constraint-test-only');
SET @example_admin = LAST_INSERT_ID();

INSERT INTO UserRole (UserID, RoleCode, GrantedByUserID) VALUES
    (@example_admin, 'Administrator', NULL),
    (@example_borrower, 'Borrower', @example_admin),
    (@example_lender, 'Lender', @example_admin);
INSERT INTO BorrowerProfile (UserID, MonthlyIncomeCipher, ExternalObligationsCipher)
VALUES (@example_borrower, X'01', X'02');

-- One borrower may have multiple requests. Submitted snapshots are required here.
INSERT INTO LoanRequest (BorrowerID, Purpose, Principal, InstallmentCount, PolicyCode,
    RequestState, SubmittedAt, FundingDeadlineAt, SubmittedIncomeCipher, SubmittedObligationsCipher)
VALUES (@example_borrower, 'Fictional equipment request', 300.00, 3, 'D1', 'Funded',
        @example_time, '2026-11-03 12:00:00', X'01', X'02');
SET @example_request = LAST_INSERT_ID();
INSERT INTO LoanRequest (BorrowerID, Purpose, Principal, InstallmentCount, PolicyCode,
    RequestState, SubmittedAt, FundingDeadlineAt, SubmittedIncomeCipher, SubmittedObligationsCipher)
VALUES (@example_borrower, 'Fictional second request', 300.00, 3, 'D1', 'Funded',
        @example_time, '2026-11-03 12:00:00', X'01', X'02');
SET @example_other_request = LAST_INSERT_ID();

INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, EvaluatedAt,
    PlatformBurdenCipher, NoDelinquencyPass, AffordabilityPass, CompletedAt, ContextID)
VALUES (@example_request, 'Submission', 0, @example_time, X'01', 1, 1, @example_time, @example_context);
SET @example_submission = LAST_INSERT_ID();
INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, EvaluatedAt,
    PlatformBurdenCipher, NoDelinquencyPass, AffordabilityPass, CompletedAt,
    AdministratorID, Decision, Reason, DecidedAt, ContextID)
VALUES (@example_request, 'Review', 1, @example_time, X'01', 1, 1, @example_time,
        @example_admin, 'Approve', 'Fictional approval', @example_time, @example_context);
SET @example_review = LAST_INSERT_ID();
INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, EvaluatedAt,
    PlatformBurdenCipher, NoDelinquencyPass, AffordabilityPass, CompletedAt, ContextID)
VALUES (@example_request, 'Funding', 1, @example_time, X'01', 1, 1, @example_time, @example_context);
SET @example_funding = LAST_INSERT_ID();
INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, EvaluatedAt,
    PlatformBurdenCipher, NoDelinquencyPass, AffordabilityPass, CompletedAt, ContextID)
VALUES (@example_request, 'Funding', 2, @example_time, X'01', 1, 1, @example_time, @example_context);
SET @example_funding_again = LAST_INSERT_ID();
INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, EvaluatedAt,
    PlatformBurdenCipher, NoDelinquencyPass, AffordabilityPass, CompletedAt, ContextID)
VALUES (@example_other_request, 'Funding', 1, @example_time, X'01', 1, 1, @example_time, @example_context);
SET @example_other_funding = LAST_INSERT_ID();

INSERT INTO OperationReceipt (CallerUserID, OperationReference, ActionCode, ReceiptSnapshot)
VALUES (@example_lender, 'schema-demo-fund-1', 'CommitFunding', X'01');
SET @example_operation = LAST_INSERT_ID();
INSERT INTO OperationReceipt (CallerUserID, OperationReference, ActionCode, ReceiptSnapshot)
VALUES (@example_lender, 'schema-demo-fund-2', 'CommitFunding', X'01');
SET @example_operation_again = LAST_INSERT_ID();
INSERT INTO OperationReceipt (CallerUserID, OperationReference, ActionCode, ReceiptSnapshot)
VALUES (@example_lender, 'schema-demo-fund-3', 'CommitFunding', X'01');
SET @example_other_operation = LAST_INSERT_ID();

-- The same lender funds the same request twice using distinct operation/evaluation IDs.
INSERT INTO FundingCommitment (RequestID, OperationID, EvaluationID, Amount, CommitmentState, AppliedAt)
VALUES (@example_request, @example_operation, @example_funding, 150.00, 'Applied', @example_time);
SET @example_commitment = LAST_INSERT_ID();
INSERT INTO FundingCommitment (RequestID, OperationID, EvaluationID, Amount, CommitmentState, AppliedAt)
VALUES (@example_request, @example_operation_again, @example_funding_again, 150.00, 'Applied', @example_time);
SET @example_commitment_again = LAST_INSERT_ID();
INSERT INTO FundingCommitment (RequestID, OperationID, EvaluationID, Amount, CommitmentState, AppliedAt)
VALUES (@example_other_request, @example_other_operation, @example_other_funding, 300.00, 'Applied', @example_time);

INSERT INTO Loan (RequestID, ActivatedAt, LastEvaluatedAt)
VALUES (@example_request, @example_time, @example_time);
SET @example_loan = LAST_INSERT_ID();
INSERT INTO Loan (RequestID, ActivatedAt, LastEvaluatedAt)
VALUES (@example_other_request, @example_time, @example_time);
SET @example_other_loan = LAST_INSERT_ID();
INSERT INTO Installment (LoanID, InstallmentNumber, DueDate, ScheduledPrincipal) VALUES
    (@example_loan, 1, '2026-11-20', 100.00),
    (@example_loan, 2, '2026-12-20', 100.00),
    (@example_loan, 3, '2027-01-20', 100.00),
    (@example_other_loan, 1, '2026-11-20', 100.00),
    (@example_other_loan, 2, '2026-12-20', 100.00),
    (@example_other_loan, 3, '2027-01-20', 100.00);

INSERT INTO OperationReceipt (CallerUserID, OperationReference, ActionCode, ReceiptSnapshot)
VALUES (@example_borrower, 'schema-demo-pay-1', 'PostRepayment', X'01');
SET @example_payment_operation = LAST_INSERT_ID();
INSERT INTO OperationReceipt (CallerUserID, OperationReference, ActionCode, ReceiptSnapshot)
VALUES (@example_borrower, 'schema-demo-pay-2', 'PostRepayment', X'01');
SET @example_payment_operation_again = LAST_INSERT_ID();
INSERT INTO OperationReceipt (CallerUserID, OperationReference, ActionCode, ReceiptSnapshot)
VALUES (@example_borrower, 'schema-demo-pay-3', 'PostRepayment', X'01');
SET @example_other_payment_operation = LAST_INSERT_ID();
INSERT INTO Repayment (LoanID, RepaymentNumber, OperationID, Amount) VALUES
    (@example_loan, 1, @example_payment_operation, 50.00),
    (@example_loan, 2, @example_payment_operation_again, 20.00),
    (@example_other_loan, 1, @example_other_payment_operation, 20.00);
INSERT INTO RepaymentAllocation (LoanID, RepaymentNumber, InstallmentNumber, AllocatedPrincipal) VALUES
    (@example_loan, 1, 1, 50.00),
    (@example_loan, 2, 1, 20.00),
    (@example_other_loan, 1, 1, 20.00);

INSERT INTO OversightNote (LoanID, AdministratorID, NoteText)
VALUES (@example_loan, @example_admin, 'Fictional follow-up');
SET @example_note = LAST_INSERT_ID();
INSERT INTO OversightNote (LoanID, AdministratorID, NoteText, CorrectsNoteID)
VALUES (@example_loan, @example_admin, 'Fictional correction', @example_note);

-- Only safe field names are recorded for private changes: both values stay NULL.
INSERT INTO AuditEvent (EventType, Outcome, ActorUserID, ActingRoleCode,
    TechnicalAccount, SubjectType, SubjectKey, ContextID)
VALUES ('ProfileSaved', 'Success', @example_borrower, 'Borrower',
        SESSION_USER(), 'BorrowerProfile', CAST(@example_borrower AS CHAR), @example_context);
SET @example_audit = LAST_INSERT_ID();
INSERT INTO AuditChange (AuditEventID, FieldName, OldValue, NewValue) VALUES
    (@example_audit, 'MonthlyIncomeCipher', NULL, NULL),
    (@example_audit, 'ExternalObligationsCipher', NULL, NULL);

-- A denied attempt can record a nonexistent target without a fabricated parent FK.
INSERT INTO AuditEvent (EventType, Outcome, TechnicalAccount, SubjectType, SubjectKey, ContextID, ReasonCode)
VALUES ('AttemptRejected', 'Denied', SESSION_USER(), 'Attempt', 'ReadDetail/999999', @example_context, 'NOT_AUTHENTICATED');

-- With the workflow trigger installed, frozen-field edits below raise 1644 before
-- table constraints run. A schema-only build retains the earlier errors noted.
-- SECTION 2: Invalid examples. Each should fail; select ONE with fresh Section 1 setup.
-- Execute the SQL after its -- prefix in Workbench, check the error, then ROLLBACK.
-- Do not run Section 3 between setup and an invalid example. Large IDs do not exist.

-- S01: request below minimum. Expected MySQL error 1644 with trigger; 3819 with schema only.
-- UPDATE LoanRequest SET Principal = 99.99 WHERE RequestID = @example_request;

-- S02: request above maximum. Expected MySQL error 1644 with trigger; 3819 with schema only.
-- UPDATE LoanRequest SET Principal = 2000.01 WHERE RequestID = @example_request;

-- S03: unsupported installment count. Expected MySQL error 1644 with trigger; 3819 with schema only.
-- UPDATE LoanRequest SET InstallmentCount = 4 WHERE RequestID = @example_request;

-- S04: blank request purpose. Expected MySQL error 1644 with trigger; 3819 with schema only.
-- UPDATE LoanRequest SET Purpose = ' ' WHERE RequestID = @example_request;

-- S05: invalid request state. Expected MySQL error 3819.
-- UPDATE LoanRequest SET RequestState = 'Unknown' WHERE RequestID = @example_request;

-- S06: wrong request-state capitalization. Expected MySQL error 3819.
-- UPDATE LoanRequest SET RequestState = 'funded' WHERE RequestID = @example_request;

-- S09: unsupported policy. Expected MySQL error 1644 with trigger; 3819 with schema only.
-- UPDATE LoanRequest SET PolicyCode = 'D2' WHERE RequestID = @example_request;

-- S12: nonexistent borrower. Expected MySQL error 1644 with trigger; 1452 with schema only.
-- UPDATE LoanRequest SET BorrowerID = 18446744073709551615 WHERE RequestID = @example_request;

-- S13: funding attempt zero. Expected MySQL error 3819.
-- UPDATE RequestEvaluation SET AttemptNumber = 0 WHERE EvaluationID = @example_funding;

-- S14: submission attempt not zero. Expected MySQL error 3819.
-- UPDATE RequestEvaluation SET AttemptNumber = 1 WHERE EvaluationID = @example_submission;

-- S15: duplicate attempt identity. Expected MySQL error 1062.
-- UPDATE RequestEvaluation SET AttemptNumber = 1 WHERE EvaluationID = @example_funding_again;

-- S16: invalid condition flag. Expected MySQL error 3819.
-- UPDATE RequestEvaluation SET NoDelinquencyPass = 2 WHERE EvaluationID = @example_funding;

-- S17: invalid affordability flag. Expected MySQL error 3819.
-- UPDATE RequestEvaluation SET AffordabilityPass = 2 WHERE EvaluationID = @example_funding;

-- S19: completion before evaluation. Expected MySQL error 3819.
-- UPDATE RequestEvaluation SET CompletedAt = '2026-10-19 12:00:00' WHERE EvaluationID = @example_funding;

-- S22: approval on failing result. Expected MySQL error 3819.
-- UPDATE RequestEvaluation SET NoDelinquencyPass = 0 WHERE EvaluationID = @example_review;

-- S24: second final review. Expected MySQL error 1062.
-- INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, EvaluatedAt, PlatformBurdenCipher, NoDelinquencyPass, AffordabilityPass, CompletedAt, AdministratorID, Decision, Reason, DecidedAt, ContextID) VALUES (@example_request, 'Review', 2, @example_time, X'01', 1, 1, @example_time, @example_admin, 'Reject', 'Fictional rejection', @example_time, @example_context);

-- S25: manually assigned generated result. Expected MySQL error 3105.
-- UPDATE RequestEvaluation SET Result = 'Pass' WHERE EvaluationID = @example_funding;

-- S26: empty exposure envelope. Expected MySQL error 3819.
-- UPDATE RequestEvaluation SET PlatformBurdenCipher = X'' WHERE EvaluationID = @example_funding;

-- S27: duplicate caller/reference. Expected MySQL error 1062.
-- UPDATE OperationReceipt SET OperationReference = 'schema-demo-fund-1' WHERE OperationID = @example_operation_again;

-- S28: unsupported receipt action. Expected MySQL error 3819.
-- UPDATE OperationReceipt SET ActionCode = 'TransferMoney' WHERE OperationID = @example_operation;

-- S29: blank operation reference. Expected MySQL error 3819.
-- UPDATE OperationReceipt SET OperationReference = ' ' WHERE OperationID = @example_operation;

-- S30: empty response snapshot. Expected MySQL error 3819.
-- UPDATE OperationReceipt SET ReceiptSnapshot = X'' WHERE OperationID = @example_operation;

-- S31: zero funding amount. Expected MySQL error 3819.
-- UPDATE FundingCommitment SET Amount = 0 WHERE CommitmentID = @example_commitment;

-- S32: negative funding amount. Expected MySQL error 3819.
-- UPDATE FundingCommitment SET Amount = -1 WHERE CommitmentID = @example_commitment;

-- S33: invalid commitment state. Expected MySQL error 3819.
-- UPDATE FundingCommitment SET CommitmentState = 'Unknown' WHERE CommitmentID = @example_commitment;

-- S34: applied commitment without application time. Expected MySQL error 3819.
-- UPDATE FundingCommitment SET AppliedAt = NULL WHERE CommitmentID = @example_commitment;

-- S35: applied and released simultaneously. Expected MySQL error 3819.
-- UPDATE FundingCommitment SET ReleasedAt = @example_time WHERE CommitmentID = @example_commitment;

-- S36: reused funding receipt. Expected MySQL error 1062.
-- UPDATE FundingCommitment SET OperationID = @example_operation WHERE CommitmentID = @example_commitment_again;

-- S37: reused funding evaluation. Expected MySQL error 1062.
-- UPDATE FundingCommitment SET EvaluationID = @example_funding WHERE CommitmentID = @example_commitment_again;

-- S38: nonexistent funding evaluation. Expected MySQL error 1452.
-- UPDATE FundingCommitment SET EvaluationID = 18446744073709551615 WHERE CommitmentID = @example_commitment;

-- S39: second loan for one request. Expected MySQL error 1062.
-- INSERT INTO Loan (RequestID, LastEvaluatedAt) VALUES (@example_request, @example_time);

-- S40: repaid loan without completion time. Expected MySQL error 3819.
-- UPDATE Loan SET LoanState = 'Repaid' WHERE LoanID = @example_loan;

-- S41: active loan with completion time. Expected MySQL error 3819.
-- UPDATE Loan SET CompletedAt = @example_time WHERE LoanID = @example_loan;

-- S42: invalid observed loan condition. Expected MySQL error 3819.
-- UPDATE Loan SET ObservedCondition = 'Unknown' WHERE LoanID = @example_loan;

-- S43: loan without an existing request. Expected MySQL error 1452.
-- UPDATE Loan SET RequestID = 18446744073709551615 WHERE LoanID = @example_loan;

-- S44: installment number zero. Expected MySQL error 3819.
-- UPDATE Installment SET InstallmentNumber = 0 WHERE LoanID = @example_loan AND InstallmentNumber = 1;

-- S45: zero scheduled principal. Expected MySQL error 3819.
-- UPDATE Installment SET ScheduledPrincipal = 0 WHERE LoanID = @example_loan AND InstallmentNumber = 1;

-- S46: duplicate due date within one loan. Expected MySQL error 1062.
-- UPDATE Installment SET DueDate = '2026-11-20' WHERE LoanID = @example_loan AND InstallmentNumber = 2;

-- S47: duplicate weak-entity key. Expected MySQL error 1062.
-- INSERT INTO Installment VALUES (@example_loan, 1, '2027-02-20', 100.00);

-- S48: zero repayment amount. Expected MySQL error 3819.
-- UPDATE Repayment SET Amount = 0 WHERE LoanID = @example_loan AND RepaymentNumber = 1;

-- S49: repayment number zero. Expected MySQL error 3819.
-- UPDATE Repayment SET RepaymentNumber = 0 WHERE LoanID = @example_loan AND RepaymentNumber = 1;

-- S50: reused repayment receipt. Expected MySQL error 1062.
-- UPDATE Repayment SET OperationID = @example_payment_operation WHERE LoanID = @example_loan AND RepaymentNumber = 2;

-- S51: zero allocation amount. Expected MySQL error 3819.
-- UPDATE RepaymentAllocation SET AllocatedPrincipal = 0 WHERE LoanID = @example_loan AND RepaymentNumber = 1;

-- S52: repayment from a different loan. Expected MySQL error 1452.
-- INSERT INTO RepaymentAllocation VALUES (@example_other_loan, 2, 2, 1.00);

-- S53: nonexistent installment in the selected loan. Expected MySQL error 1452.
-- INSERT INTO RepaymentAllocation VALUES (@example_loan, 1, 99, 1.00);

-- S54: duplicate allocation pair. Expected MySQL error 1062.
-- INSERT INTO RepaymentAllocation VALUES (@example_loan, 1, 1, 1.00);

-- S55: blank oversight note. Expected MySQL error 3819.
-- UPDATE OversightNote SET NoteText = ' ' WHERE NoteID = @example_note;

-- S56: note without a target. Expected MySQL error 3819.
-- UPDATE OversightNote SET LoanID = NULL WHERE NoteID = @example_note;

-- S57: note with two targets. Expected MySQL error 3819.
-- UPDATE OversightNote SET RequestID = @example_request WHERE NoteID = @example_note;

-- S58: correction of a nonexistent note. Expected MySQL error 1452.
-- UPDATE OversightNote SET CorrectsNoteID = 18446744073709551615 WHERE NoteID = @example_note;

-- S59: unsupported audit event. Expected MySQL error 3819.
-- UPDATE AuditEvent SET EventType = 'Unknown' WHERE AuditEventID = @example_audit;

-- S64: unsupported audit reason. Expected MySQL error 3819.
-- UPDATE AuditEvent SET ReasonCode = 'RAW_ERROR_MESSAGE' WHERE AuditEventID = @example_audit;

-- S65: denial without reason. Expected MySQL error 3819.
-- UPDATE AuditEvent SET EventType = 'AttemptRejected', SubjectType = 'Attempt', Outcome = 'Denied', ReasonCode = NULL WHERE AuditEventID = @example_audit;

-- S66: private value leaking into audit. Expected MySQL error 3819.
-- UPDATE AuditChange SET NewValue = 'private data' WHERE AuditEventID = @example_audit AND FieldName = 'MonthlyIncomeCipher';

-- S67: unsupported audit field. Expected MySQL error 3819.
-- UPDATE AuditChange SET FieldName = 'NoteText' WHERE AuditEventID = @example_audit AND FieldName = 'MonthlyIncomeCipher';

-- S68: duplicate changed field. Expected MySQL error 1062.
-- INSERT INTO AuditChange VALUES (@example_audit, 'MonthlyIncomeCipher', NULL, NULL);

-- S69: audit change without a parent event. Expected MySQL error 1452.
-- INSERT INTO AuditChange VALUES (18446744073709551615, 'AccountStatus', NULL, 'Active');

-- S70: blank retained status reason. Expected MySQL error 3819.
-- INSERT INTO AuditChange VALUES (@example_audit, 'StatusReason', NULL, ' ');

-- S71: deleting a retained request. Expected error 1644 from trg_request_no_delete
-- (before the FK check; the earlier schema-only expectation was 1451).
-- DELETE FROM LoanRequest WHERE RequestID = @example_request;

-- SECTION 2B: Deferred workflow rules. W01/W02 now fail under the snapshot trigger.
-- The remaining statements still succeed at table level.
-- They are NOT valid application actions. Future controlled operations must reject them.
-- To inspect one: run fresh Section 1, select the SQL after --, execute it, then ROLLBACK.
-- The full-file runner skips these commented examples just like the invalid examples.

-- W01: missing submitted snapshot (formerly S07). Expected error 1644 with trigger; success with schema only.
-- UPDATE LoanRequest SET SubmittedIncomeCipher = NULL WHERE RequestID = @example_request;

-- W02: empty submitted snapshot (formerly S08). Expected error 1644 with trigger; success with schema only.
-- UPDATE LoanRequest SET SubmittedObligationsCipher = X'' WHERE RequestID = @example_request;

-- W03: missing funding deadline (formerly S10). Expected SQL success; workflow validation pending.
-- UPDATE LoanRequest SET FundingDeadlineAt = NULL WHERE RequestID = @example_request;

-- W04: cancellation without reason (formerly S11). Expected SQL success; workflow validation pending.
-- UPDATE LoanRequest SET RequestState = 'Cancelled' WHERE RequestID = @example_request;

-- W05: incomplete funding check (formerly S18). Expected SQL success; workflow validation pending.
-- UPDATE RequestEvaluation SET CompletedAt = NULL WHERE EvaluationID = @example_funding;

-- W06: review without administrator (formerly S20). Expected SQL success; workflow validation pending.
-- UPDATE RequestEvaluation SET AdministratorID = NULL WHERE EvaluationID = @example_review;

-- W07: administrator on a non-review check (formerly S21). Expected SQL success; workflow validation pending.
-- UPDATE RequestEvaluation SET AdministratorID = @example_admin WHERE EvaluationID = @example_funding;

-- W08: incomplete decision context (formerly S23). Expected SQL success; workflow validation pending.
-- UPDATE RequestEvaluation SET Reason = NULL WHERE EvaluationID = @example_review;

-- W09: wrong event subject (formerly S60). Expected SQL success; workflow validation pending.
-- UPDATE AuditEvent SET SubjectType = 'Loan' WHERE AuditEventID = @example_audit;

-- W10: wrong event outcome (formerly S61). Expected SQL success; workflow validation pending.
-- UPDATE AuditEvent SET Outcome = 'Denied', ReasonCode = 'INVALID_INPUT' WHERE AuditEventID = @example_audit;

-- W11: wrong acting role for the event (formerly S62). Expected SQL success; workflow validation pending.
-- UPDATE AuditEvent SET ActingRoleCode = 'Lender' WHERE AuditEventID = @example_audit;

-- W12: human success without an actor (formerly S63). Expected SQL success; workflow validation pending.
-- UPDATE AuditEvent SET ActorUserID = NULL WHERE AuditEventID = @example_audit;

-- SECTION 3: Valid examples. Compare displayed values with these expectations.
-- P01: Expected request_count = 2: BorrowerID is deliberately NOT unique.
SELECT COUNT(*) AS request_count FROM LoanRequest WHERE BorrowerID = @example_borrower;

-- P02: Expected contribution_count = 2 and pledged_principal = 300.00.
SELECT COUNT(*) AS contribution_count, SUM(Amount) AS pledged_principal
FROM FundingCommitment WHERE RequestID = @example_request;

-- P03: Expected Pass and final marker 1 for the approved review.
SELECT Result, FinalReviewMarker FROM RequestEvaluation WHERE EvaluationID = @example_review;

-- A pending Submission may omit completion; its generated Result is NULL.
INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, PlatformBurdenCipher,
    NoDelinquencyPass, ContextID)
VALUES (@example_other_request, 'Submission', 0, X'01', 1, @example_context);
SELECT Result IS NULL AS pending_result_is_null FROM RequestEvaluation WHERE EvaluationID = LAST_INSERT_ID();

-- Completed nonfinal review attempts may coexist with the one final review.
INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber, EvaluatedAt,
    PlatformBurdenCipher, NoDelinquencyPass, AffordabilityPass, CompletedAt, AdministratorID, ContextID)
VALUES (@example_request, 'Review', 2, @example_time, X'01', 0, 1, @example_time, @example_admin, @example_context),
       (@example_request, 'Review', 3, @example_time, X'01', 0, 1, @example_time, @example_admin, @example_context);
-- Expected: one Pass/1 row and two Fail/NULL rows.
SELECT Result, FinalReviewMarker FROM RequestEvaluation
WHERE RequestID = @example_request AND EvaluationKind = 'Review' ORDER BY AttemptNumber;

-- P04: Both loans may have installment 1. Expected loan_count = 2.
SELECT COUNT(*) AS loan_count FROM Installment
WHERE LoanID IN (@example_loan, @example_other_loan) AND InstallmentNumber = 1;

-- P05: Expected allocated_total = 70.00 across two payments on the first loan.
SELECT SUM(AllocatedPrincipal) AS allocated_total
FROM RepaymentAllocation WHERE LoanID = @example_loan;

-- P06: The audit contains field names without private values. Expected 2 rows, NULL/NULL.
SELECT FieldName, OldValue, NewValue FROM AuditChange WHERE AuditEventID = @example_audit ORDER BY FieldName;

-- SECTION 4: Undo ALL demonstration rows, including the late positive examples.
ROLLBACK;
-- Every count below should be 0. The four seeded Role rows are unchanged.
SELECT COUNT(*) AS demo_users_remaining FROM `User`
WHERE UserID IN (@example_borrower, @example_lender, @example_admin);
SELECT COUNT(*) AS demo_requests_remaining FROM LoanRequest
WHERE RequestID IN (@example_request, @example_other_request);
SELECT COUNT(*) AS demo_loans_remaining FROM Loan WHERE LoanID IN (@example_loan, @example_other_loan);
SELECT COUNT(*) AS demo_audit_rows_remaining FROM AuditEvent WHERE ContextID = @example_context;
