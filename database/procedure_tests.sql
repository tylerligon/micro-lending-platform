-- ONLY for the disposable database created by build/test_create_loan_request.sh.
-- Unlike table walkthroughs, CALL commits its own transaction. Outer ROLLBACK will
-- not undo it. The runner drops this dedicated test database after successful tests.
USE micro_lending_procedure_test;

-- SECTION 1: Fictional setup, not usable encrypted data or application credentials.
-- The database must have a fresh schema, roles, and sp_create_loan_request installed.
INSERT INTO `User` (UserID, LoginName, DisplayName, PublicAlias, PrivateEmailCipher,
    PasswordHash, AccountStatus) VALUES
    (1, 'proc_borrower', 'Procedure Borrower', 'proc_borrower', X'01', 'constraint-test-only', 'Active'),
    (2, 'proc_restricted', 'Restricted Borrower', 'proc_restricted', X'01', 'constraint-test-only', 'Restricted'),
    (3, 'proc_inactive', 'Inactive Borrower', 'proc_inactive', X'01', 'constraint-test-only', 'Inactive'),
    (4, 'proc_no_role', 'No Borrower Role', 'proc_no_role', X'01', 'constraint-test-only', 'Active'),
    (5, 'proc_revoked', 'Revoked Borrower', 'proc_revoked', X'01', 'constraint-test-only', 'Active'),
    (6, 'proc_no_profile', 'No Profile', 'proc_no_profile', X'01', 'constraint-test-only', 'Active'),
    (7, 'proc_admin', 'Procedure Administrator', 'proc_admin', X'01', 'constraint-test-only', 'Active');

INSERT INTO UserRole (UserID, RoleCode, GrantedAt, GrantedByUserID) VALUES
    (7, 'Administrator', '2026-10-20 12:00:00', NULL),
    (1, 'Borrower', '2026-10-20 12:00:00', 7),
    (2, 'Borrower', '2026-10-20 12:00:00', 7),
    (3, 'Borrower', '2026-10-20 12:00:00', 7),
    (6, 'Borrower', '2026-10-20 12:00:00', 7);
INSERT INTO UserRole (UserID, RoleCode, GrantedAt, GrantedByUserID, RevokedAt, RevokedByUserID)
VALUES (5, 'Borrower', '2026-10-20 12:00:00', 7, '2026-10-20 12:01:00', 7);
INSERT INTO BorrowerProfile (UserID, MonthlyIncomeCipher, ExternalObligationsCipher) VALUES
    (1, X'01', X'02'), (2, X'01', X'02'), (3, X'01', X'02'),
    (4, X'01', X'02'), (5, X'01', X'02');

-- SECTION 2: Invalid calls. Run one at a time in the isolated test database.
-- Each should return MySQL error 1644 with the procedure's validation message.
-- Compare request/audit counts before and after: a rejected call must add no rows.
-- Do not use an outer transaction to clean up CALL; this procedure owns its transaction.

-- P01: missing borrower ID. Expected MySQL error 1644.
-- CALL sp_create_loan_request(NULL, 'Equipment', 300.00, 3);

-- P02: nonexistent borrower. Expected MySQL error 1644.
-- CALL sp_create_loan_request(999999, 'Equipment', 300.00, 3);

-- P03: restricted account. Expected MySQL error 1644.
-- CALL sp_create_loan_request(2, 'Equipment', 300.00, 3);

-- P04: inactive account. Expected MySQL error 1644.
-- CALL sp_create_loan_request(3, 'Equipment', 300.00, 3);

-- P05: missing Borrower role. Expected MySQL error 1644.
-- CALL sp_create_loan_request(4, 'Equipment', 300.00, 3);

-- P06: revoked Borrower role. Expected MySQL error 1644.
-- CALL sp_create_loan_request(5, 'Equipment', 300.00, 3);

-- P07: missing borrower profile. Expected MySQL error 1644.
-- CALL sp_create_loan_request(6, 'Equipment', 300.00, 3);

-- P08: missing purpose. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, NULL, 300.00, 3);

-- P09: blank purpose. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, '   ', 300.00, 3);

-- P10: purpose longer than 1000 characters. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, REPEAT('x', 1001), 300.00, 3);

-- P11: missing principal. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, 'Equipment', NULL, 3);

-- P12: below minimum principal. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, 'Equipment', 99.99, 3);

-- P13: above maximum principal. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, 'Equipment', 2000.01, 3);

-- P14: zero principal. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, 'Equipment', 0, 3);

-- P15: negative principal. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, 'Equipment', -1.00, 3);

-- P16: missing installment count. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, 'Equipment', 300.00, NULL);

-- P17: unsupported installment count. Expected MySQL error 1644.
-- CALL sp_create_loan_request(1, 'Equipment', 300.00, 4);

-- SECTION 3: Valid calls. Same borrower can create multiple separate Drafts.
-- Expected: three new RequestIDs, each returned with Draft and RowVersion 0.
CALL sp_create_loan_request(1, ' Equipment purchase ', 300.00, 3);
CALL sp_create_loan_request(1, 'Minimum boundary', 100.00, 6);
CALL sp_create_loan_request(1, 'Maximum boundary', 2000.00, 3);

-- Expected: 3 requests, normalized purpose, correct amounts/terms, Draft, version 0.
-- All submission fields below must remain NULL.
SELECT BorrowerID, Purpose, Principal, InstallmentCount, RequestState, RowVersion,
       SubmittedAt, PolicyCode, SubmittedIncomeCipher, SubmittedObligationsCipher
FROM LoanRequest ORDER BY RequestID;

-- Expected: 3 successful RequestSaved events for actor 1 and 12 changed-field rows.
SELECT COUNT(*) AS saved_events FROM AuditEvent
WHERE EventType = 'RequestSaved' AND Outcome = 'Success' AND ActorUserID = 1;
SELECT COUNT(*) AS changed_fields FROM AuditChange;
SELECT FieldName, OldValue, NewValue FROM AuditChange
WHERE AuditEventID = 1 ORDER BY FieldName;

-- SECTION 4: Optional controlled failure demonstration, in this test DB only.
-- After Section 3, uncomment and execute the following statements individually.
-- The trigger is a temporary test tool: it forces failure after the request and
-- AuditEvent inserts. The failed CALL must roll back both of those inserts.
-- CREATE TRIGGER force_draft_audit_failure BEFORE INSERT ON AuditChange
-- FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Forced audit failure';
-- CALL sp_create_loan_request(1, 'Rollback example', 300.00, 3);
-- Expected: error 1644, then counts still 3 requests, 3 events, 12 changes.
-- SELECT (SELECT COUNT(*) FROM LoanRequest) AS requests_after_error,
--        (SELECT COUNT(*) FROM AuditEvent) AS events_after_error,
--        (SELECT COUNT(*) FROM AuditChange) AS changes_after_error;
-- COMMIT;
-- DROP TRIGGER force_draft_audit_failure;
