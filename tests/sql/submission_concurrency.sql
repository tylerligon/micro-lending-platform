-- MANUAL two-connection demonstration. ONLY use micro_lending_workflow_test.
-- Run the CREATE/load commands from build/test_early_workflows.sh, stopping BEFORE
-- early_workflows.sql. This file needs those objects and an otherwise empty DB.
-- Run only the indicated section in each connection, not this whole file as a batch.
USE micro_lending_workflow_test;

-- 1. SETUP: run once, on connection A. Dummy bytes are not real encryption.
INSERT INTO `User` (UserID, LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
VALUES (1, 'race_admin', 'Race Admin', 'race_admin', X'01', 'test-only'),
       (2, 'race_borrower', 'Race Borrower', 'race_borrower', X'01', 'test-only');
INSERT INTO UserRole (UserID, RoleCode) VALUES (1, 'Administrator'), (2, 'Borrower');
CALL sp_save_profile(2, NULL, '1000.00', '100.00', X'01', X'02');
CALL sp_create_loan_request(2, 'First concurrent request', '1200.00', 3);
CALL sp_create_loan_request(2, 'Second concurrent request', '1200.00', 3);

-- 2. CONNECTION A: run prepare only. Expected PlatformBurden = 0.00; leave locks held.
CALL sp_prepare_submission(2, 1, 0);

-- 3. CONNECTION B: select the same DB and run prepare. It WAITS for A's borrower lock.
-- USE micro_lending_workflow_test;
-- CALL sp_prepare_submission(2, 2, 0);

-- 4. CONNECTION A: finish. B's prepare now returns PlatformBurden = 400.00.
CALL sp_submit_request(2, 1, @ml_submit_context, '1000.00', '100.00', X'11', X'12', X'13');

-- 5. CONNECTION B: finish using B's own prepared context.
-- CALL sp_submit_request(2, 2, @ml_submit_context, '1000.00', '100.00', X'21', X'22', X'23');

-- 6. VERIFY on A: two Submitted requests, two incomplete Submission evaluations.
-- Both submissions succeed; later assessment must consider the distinct snapshots.
-- With the retained inputs, the first proposed 400 fits 900; the second has
-- 400 existing + 400 proposed + 100 external = 900, also fits income 1000.
-- Change both requests to 1500/3 on a fresh run to demonstrate 500+500+100 > 1000
-- at later assessment. Assessment itself is outside this implementation stage.
SELECT RequestID, RequestState FROM LoanRequest ORDER BY RequestID;
SELECT RequestID, EvaluationKind, AttemptNumber, AffordabilityPass, CompletedAt
FROM RequestEvaluation ORDER BY RequestID;

-- 7. Close/rollback both test connections, then drop ONLY this disposable database.
-- DROP DATABASE micro_lending_workflow_test;
