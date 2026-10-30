-- ONE-TIME from 1deed92. Backup first; DDL is not atomic. Never run on a live server during use.
-- Retains users, role episodes, requests, and audit rows. Do not retry partial DDL blindly.
SET @constraint_name=(SELECT tc.CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS tc
 JOIN information_schema.CHECK_CONSTRAINTS cc ON cc.CONSTRAINT_SCHEMA=tc.CONSTRAINT_SCHEMA AND cc.CONSTRAINT_NAME=tc.CONSTRAINT_NAME
 WHERE tc.CONSTRAINT_SCHEMA=DATABASE() AND tc.TABLE_NAME='Role' AND cc.CHECK_CLAUSE LIKE '%Borrower%'
 AND tc.CONSTRAINT_TYPE='CHECK' LIMIT 1);
SET @ddl=CONCAT('ALTER TABLE `Role` DROP CHECK `',@constraint_name,'`');
PREPARE migration_stmt FROM @ddl; EXECUTE migration_stmt; DEALLOCATE PREPARE migration_stmt;
SET @constraint_name=(SELECT tc.CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS tc
 JOIN information_schema.CHECK_CONSTRAINTS cc ON cc.CONSTRAINT_SCHEMA=tc.CONSTRAINT_SCHEMA AND cc.CONSTRAINT_NAME=tc.CONSTRAINT_NAME
 WHERE tc.CONSTRAINT_SCHEMA=DATABASE() AND tc.TABLE_NAME='AuditEvent' AND cc.CHECK_CLAUSE LIKE '%UserCreated%'
 AND tc.CONSTRAINT_TYPE='CHECK' LIMIT 1);
SET @ddl=CONCAT('ALTER TABLE `AuditEvent` DROP CHECK `',@constraint_name,'`');
PREPARE migration_stmt FROM @ddl; EXECUTE migration_stmt; DEALLOCATE PREPARE migration_stmt;
SET @constraint_name=(SELECT tc.CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS tc
 JOIN information_schema.CHECK_CONSTRAINTS cc ON cc.CONSTRAINT_SCHEMA=tc.CONSTRAINT_SCHEMA AND cc.CONSTRAINT_NAME=tc.CONSTRAINT_NAME
 WHERE tc.CONSTRAINT_SCHEMA=DATABASE() AND tc.TABLE_NAME='AuditChange' AND cc.CHECK_CLAUSE LIKE '%ActivatedAt%'
 AND tc.CONSTRAINT_TYPE='CHECK' LIMIT 1);
SET @ddl=CONCAT('ALTER TABLE `AuditChange` DROP CHECK `',@constraint_name,'`');
PREPARE migration_stmt FROM @ddl; EXECUTE migration_stmt; DEALLOCATE PREPARE migration_stmt;
ALTER TABLE `Role` ADD RoleClass VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'Borrower',
 ADD IsActive BOOLEAN NOT NULL DEFAULT TRUE, ADD RowVersion BIGINT UNSIGNED NOT NULL DEFAULT 0,
 ADD CHECK (RoleClass IN ('Borrower','Lender','Administrator','Auditor')),
 ADD CHECK (IsActive IN(0,1)), ADD CHECK(CHAR_LENGTH(TRIM(RoleCode)) BETWEEN 1 AND 16);
UPDATE `Role` SET RoleClass=RoleCode;
ALTER TABLE AuditEvent ADD CHECK (EventType IN (
        'PasswordProvisioned', 'RoleConfigured', 'PermissionConfigured', 'UserCreated', 'AccountStatusChanged', 'RoleGranted', 'RoleRevoked', 'ProfileSaved',
        'RequestSaved', 'RequestSubmitted', 'AssessmentCompleted', 'ReviewApproved',
        'ReviewRejected', 'CommitmentAccepted', 'CommitmentApplied', 'LoanActivated',
        'RequestCancelled', 'RequestExpired', 'CommitmentReleased', 'RepaymentPosted',
        'LoanCompleted', 'DelinquencyChanged', 'NoteAppended', 'AttemptRejected',
        'TransactionFailed', 'InterruptionObserved'
    ));
ALTER TABLE AuditChange ADD CHECK (FieldName IN (
        'AccountStatus', 'ActivatedAt', 'AffordabilityPass', 'AllocationCount', 'Amount',
        'AppliedAt', 'CommitmentState', 'CompletedAt', 'CorrectsNoteID', 'DecidedAt', 'Decision',
        'EvaluationID', 'ExternalObligationsCipher', 'FundingDeadlineAt', 'GrantedAt',
        'InstallmentCount', 'LastEvaluatedAt', 'LoanID', 'LoanState', 'LoginName',
        'MonthlyIncomeCipher', 'NoDelinquencyPass', 'ObservedCondition', 'OldestOverdueDueDate',
        'OutstandingAfter', 'OutstandingBefore', 'OverduePrincipal', 'PasswordHash',
        'PendingTotal', 'PolicyCode', 'Principal', 'PrivateEmailCipher', 'PublicAlias',
        'Purpose', 'ReleasedAt', 'RequestID', 'RequestState', 'Result', 'RevokedAt', 'RoleCode',
        'Configuration', 'StatusReason', 'SubmittedAt', 'SubmittedIncomeCipher', 'SubmittedObligationsCipher',
        'TerminalReason', 'UserID'
    ));

SET @c=(SELECT tc.CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS tc JOIN information_schema.CHECK_CONSTRAINTS cc ON cc.CONSTRAINT_SCHEMA=tc.CONSTRAINT_SCHEMA AND cc.CONSTRAINT_NAME=tc.CONSTRAINT_NAME WHERE tc.CONSTRAINT_SCHEMA=DATABASE() AND tc.TABLE_NAME='AuditEvent' AND cc.CHECK_CLAUSE LIKE '%SubjectType%' LIMIT 1);
SET @ddl=CONCAT('ALTER TABLE AuditEvent DROP CHECK `',@c,'`'); PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
ALTER TABLE AuditEvent ADD CHECK (SubjectType IN ('Role', 'RolePermission', 'User', 'UserRole', 'BorrowerProfile', 'LoanRequest', 'RequestEvaluation', 'FundingCommitment', 'Loan', 'Repayment', 'OversightNote', 'Attempt'));
