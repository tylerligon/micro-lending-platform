-- ONE-TIME upgrade from 189ed0f, with callers stopped and a backup taken.
-- DDL auto-commits. On partial failure inspect before retrying; no business rows reset.
SET @constraint_name=(SELECT tc.CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS tc
 JOIN information_schema.CHECK_CONSTRAINTS cc ON cc.CONSTRAINT_SCHEMA=tc.CONSTRAINT_SCHEMA AND cc.CONSTRAINT_NAME=tc.CONSTRAINT_NAME
 WHERE tc.CONSTRAINT_SCHEMA=DATABASE() AND tc.TABLE_NAME='AuditEvent'
 AND tc.CONSTRAINT_TYPE='CHECK' AND cc.CHECK_CLAUSE LIKE '%`EventType`%' LIMIT 1);
SET @ddl=CONCAT('ALTER TABLE AuditEvent DROP CHECK `',@constraint_name,'`');
PREPARE workflow_migration FROM @ddl; EXECUTE workflow_migration; DEALLOCATE PREPARE workflow_migration;
ALTER TABLE AuditEvent ADD CHECK (EventType IN (
        'WorkflowConfigured', 'PasswordProvisioned', 'RoleConfigured', 'PermissionConfigured', 'UserCreated', 'AccountStatusChanged', 'RoleGranted', 'RoleRevoked', 'ProfileSaved',
        'RequestSaved', 'RequestSubmitted', 'AssessmentCompleted', 'ReviewApproved',
        'ReviewRejected', 'CommitmentAccepted', 'CommitmentApplied', 'LoanActivated',
        'RequestCancelled', 'RequestExpired', 'CommitmentReleased', 'RepaymentPosted',
        'LoanCompleted', 'DelinquencyChanged', 'NoteAppended', 'AttemptRejected',
        'TransactionFailed', 'InterruptionObserved'
    ));
SET @constraint_name=(SELECT tc.CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS tc
 JOIN information_schema.CHECK_CONSTRAINTS cc ON cc.CONSTRAINT_SCHEMA=tc.CONSTRAINT_SCHEMA AND cc.CONSTRAINT_NAME=tc.CONSTRAINT_NAME
 WHERE tc.CONSTRAINT_SCHEMA=DATABASE() AND tc.TABLE_NAME='AuditEvent'
 AND tc.CONSTRAINT_TYPE='CHECK' AND cc.CHECK_CLAUSE LIKE '%`SubjectType`%' LIMIT 1);
SET @ddl=CONCAT('ALTER TABLE AuditEvent DROP CHECK `',@constraint_name,'`');
PREPARE workflow_migration FROM @ddl; EXECUTE workflow_migration; DEALLOCATE PREPARE workflow_migration;
ALTER TABLE AuditEvent ADD CHECK (SubjectType IN ('WorkflowTransition', 'Role', 'RolePermission', 'User', 'UserRole', 'BorrowerProfile', 'LoanRequest', 'RequestEvaluation', 'FundingCommitment', 'Loan', 'Repayment', 'OversightNote', 'Attempt'));
DROP PROCEDURE sp_lock_policy;
DROP PROCEDURE sp_auth_lookup;
DROP PROCEDURE sp_session_user;
DROP PROCEDURE sp_failure_exists;
DROP PROCEDURE sp_record_failure;
DROP PROCEDURE sp_require_permission;
DROP PROCEDURE sp_protect_access_admin;
DROP PROCEDURE sp_configure_role;
DROP PROCEDURE sp_configure_permission;
DROP PROCEDURE sp_read_requests;
DROP PROCEDURE sp_read_loan;
DROP PROCEDURE sp_lock_users;
DROP PROCEDURE sp_require_role;
DROP PROCEDURE sp_require_no_live_participation;
DROP PROCEDURE sp_early_audit;
DROP PROCEDURE sp_submission_exposure;
DROP PROCEDURE sp_create_loan_request;
DROP PROCEDURE sp_create_user;
DROP PROCEDURE sp_set_role;
DROP PROCEDURE sp_set_account_status;
DROP PROCEDURE sp_save_profile;
DROP PROCEDURE sp_update_loan_request;
DROP PROCEDURE sp_clear_submission;
DROP PROCEDURE sp_prepare_submission;
DROP PROCEDURE sp_submit_request;
DROP PROCEDURE sp_cancel_draft;
-- Keep request contexts binary; an unset user variable otherwise has a text type.
DELIMITER //
CREATE FUNCTION fn_action_context() RETURNS BINARY(16)
NOT DETERMINISTIC NO SQL
BEGIN
 IF @ml_context IS NULL THEN RETURN UUID_TO_BIN(UUID()); END IF;
 IF OCTET_LENGTH(@ml_context) <> 16 THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid action context';
 END IF;
 RETURN CAST(@ml_context AS BINARY(16));
END //
DELIMITER ;
