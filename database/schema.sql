-- Create all 15 tables in dependency order. Load role seed data separately.
-- See docs/Milestones.md for the SQL walkthrough and remaining enforcement work.

CREATE TABLE `User` (
    UserID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    -- Inherit the database default: usernames compare case-insensitively.
    LoginName VARCHAR(80) NOT NULL,
    DisplayName VARCHAR(120) NOT NULL,
    PublicAlias VARCHAR(40) NOT NULL,

    PrivateEmailCipher VARBINARY(512) NOT NULL,
    PasswordHash VARCHAR(255) NOT NULL,
    AccountStatus VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'Active',
    CreatedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    RowVersion BIGINT UNSIGNED NOT NULL DEFAULT 0,

    UNIQUE (LoginName),
    UNIQUE (PublicAlias),

    CHECK (CHAR_LENGTH(TRIM(LoginName)) > 0),
    CHECK (CHAR_LENGTH(TRIM(DisplayName)) > 0),
    CHECK (CHAR_LENGTH(TRIM(PublicAlias)) > 0),
    CHECK (AccountStatus IN ('Active', 'Restricted', 'Inactive'))
) ENGINE = InnoDB;

CREATE TABLE `Role` (
    RoleCode VARCHAR(16) COLLATE utf8mb4_0900_bin PRIMARY KEY,
    Description VARCHAR(255) NOT NULL,

    CHECK (
        RoleCode IN ('Borrower', 'Lender', 'Administrator', 'Auditor')
    ),
    CHECK (CHAR_LENGTH(TRIM(Description)) > 0)
) ENGINE = InnoDB;

CREATE TABLE UserRole (
    UserRoleID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    UserID BIGINT UNSIGNED NOT NULL,
    RoleCode VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
    GrantedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    GrantedByUserID BIGINT UNSIGNED NULL,
    RevokedAt DATETIME(6) NULL,
    RevokedByUserID BIGINT UNSIGNED NULL,

    ActiveMarker TINYINT GENERATED ALWAYS AS (IF(RevokedAt IS NULL, 1, NULL)) VIRTUAL,

    UNIQUE (UserID, RoleCode, ActiveMarker),

    FOREIGN KEY (UserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (RoleCode)
        REFERENCES `Role` (RoleCode) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (GrantedByUserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (RevokedByUserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,

    CHECK (
        (RevokedAt IS NULL AND RevokedByUserID IS NULL)
        OR (RevokedAt IS NOT NULL AND RevokedByUserID IS NOT NULL)
    ),
    CHECK (
        RevokedAt IS NULL OR RevokedAt >= GrantedAt
    )
) ENGINE = InnoDB;

-- FR-05: one current financial profile per account; values are encrypted by the service.
CREATE TABLE BorrowerProfile (
    -- Reuse the account ID: it is both this table's primary key and a foreign key.
    UserID BIGINT UNSIGNED PRIMARY KEY,
    MonthlyIncomeCipher VARBINARY(128) NOT NULL,
    ExternalObligationsCipher VARBINARY(128) NOT NULL,
    UpdatedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    RowVersion BIGINT UNSIGNED NOT NULL DEFAULT 0,

    FOREIGN KEY (UserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,

    -- Require some bytes; these checks do not verify encryption or financial amounts.
    CHECK (OCTET_LENGTH(MonthlyIncomeCipher) > 0),
    CHECK (OCTET_LENGTH(ExternalObligationsCipher) > 0)
) ENGINE = InnoDB;

-- FR-06–16: a request keeps its terms and, after submission, private input snapshots.
CREATE TABLE LoanRequest (
    RequestID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    BorrowerID BIGINT UNSIGNED NOT NULL,
    Purpose VARCHAR(1000) NOT NULL,
    Principal DECIMAL(18,2) NOT NULL,
    InstallmentCount SMALLINT UNSIGNED NOT NULL,
    PolicyCode VARCHAR(8) COLLATE utf8mb4_0900_bin NULL,
    RequestState VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'Draft',
    CreatedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    SubmittedAt DATETIME(6) NULL,
    FundingDeadlineAt DATETIME(6) NULL,
    TerminalReason VARCHAR(1000) NULL,
    RowVersion BIGINT UNSIGNED NOT NULL DEFAULT 0,
    SubmittedIncomeCipher VARBINARY(128) NULL,
    SubmittedObligationsCipher VARBINARY(128) NULL,

    FOREIGN KEY (BorrowerID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,

    -- Controlled submission/cancellation operations must validate the related workflow fields.
    CHECK (CHAR_LENGTH(TRIM(Purpose)) > 0),
    CHECK (Principal BETWEEN 100.00 AND 2000.00),
    CHECK (InstallmentCount IN (3, 6)),
    CHECK (RequestState IN ('Draft', 'Submitted', 'PendingReview', 'OpenFunding',
                           'Funded', 'Rejected', 'Cancelled', 'Expired')),
    CHECK (PolicyCode IS NULL OR PolicyCode = 'D1'),
    CHECK (TerminalReason IS NULL OR CHAR_LENGTH(TRIM(TerminalReason)) > 0)
) ENGINE = InnoDB;

-- FR-07–09/12: separate retained eligibility checks and the final human review.
CREATE TABLE RequestEvaluation (
    EvaluationID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    RequestID BIGINT UNSIGNED NOT NULL,
    EvaluationKind VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
    AttemptNumber INT UNSIGNED NOT NULL,
    EvaluatedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    PlatformBurdenCipher VARBINARY(128) NOT NULL,
    NoDelinquencyPass TINYINT UNSIGNED NOT NULL,
    AffordabilityPass TINYINT UNSIGNED NULL,
    CompletedAt DATETIME(6) NULL,
    Result VARCHAR(4) COLLATE utf8mb4_0900_bin GENERATED ALWAYS AS (
        CASE WHEN CompletedAt IS NULL THEN NULL
             WHEN AffordabilityPass = 1 AND NoDelinquencyPass = 1 THEN 'Pass'
             ELSE 'Fail' END
    ) VIRTUAL,
    AdministratorID BIGINT UNSIGNED NULL,
    Decision VARCHAR(8) COLLATE utf8mb4_0900_bin NULL,
    Reason VARCHAR(1000) NULL,
    DecidedAt DATETIME(6) NULL,
    ContextID BINARY(16) NOT NULL,
    FinalReviewMarker TINYINT GENERATED ALWAYS AS (
        IF(EvaluationKind = 'Review' AND Decision IS NOT NULL, 1, NULL)
    ) VIRTUAL,

    UNIQUE (RequestID, EvaluationKind, AttemptNumber),
    UNIQUE (RequestID, FinalReviewMarker),
    FOREIGN KEY (RequestID)
        REFERENCES LoanRequest (RequestID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (AdministratorID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,

    -- Reviewer identity and complete decision context require future controlled operations.
    CHECK (EvaluationKind IN ('Submission', 'Review', 'Funding')),
    CHECK ((EvaluationKind = 'Submission' AND AttemptNumber = 0)
           OR (EvaluationKind IN ('Review', 'Funding') AND AttemptNumber > 0)),
    CHECK (OCTET_LENGTH(PlatformBurdenCipher) > 0),
    CHECK (NoDelinquencyPass IN (0, 1)),
    CHECK (AffordabilityPass IS NULL OR AffordabilityPass IN (0, 1)),
    CHECK (CompletedAt IS NULL OR CompletedAt >= EvaluatedAt),
    CHECK (Decision IS NULL OR Decision IN ('Approve', 'Reject')),
    CHECK (Decision IS NULL OR Decision <> 'Approve' OR (Result IS NOT NULL AND Result = 'Pass'))
) ENGINE = InnoDB;

-- FR-30: one caller/reference identifies a retryable financial operation.
CREATE TABLE OperationReceipt (
    OperationID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    CallerUserID BIGINT UNSIGNED NOT NULL,
    OperationReference VARCHAR(64) COLLATE utf8mb4_0900_bin NOT NULL,
    ActionCode VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL,
    ReceiptSnapshot MEDIUMBLOB NULL,

    UNIQUE (CallerUserID, OperationReference),
    FOREIGN KEY (CallerUserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CHECK (CHAR_LENGTH(TRIM(OperationReference)) > 0),
    CHECK (ActionCode IN ('CommitFunding', 'PostRepayment')),
    -- NULL is allowed while the transaction creates its event and final response.
    CHECK (ReceiptSnapshot IS NULL OR OCTET_LENGTH(ReceiptSnapshot) > 0)
) ENGINE = InnoDB;

-- FR-12–16: repeated contributions by the same lender/request remain separate events.
CREATE TABLE FundingCommitment (
    CommitmentID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    RequestID BIGINT UNSIGNED NOT NULL,
    OperationID BIGINT UNSIGNED NOT NULL,
    EvaluationID BIGINT UNSIGNED NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    CommitmentState VARCHAR(8) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'Pending',
    CreatedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    AppliedAt DATETIME(6) NULL,
    ReleasedAt DATETIME(6) NULL,

    UNIQUE (OperationID),
    UNIQUE (EvaluationID),
    FOREIGN KEY (RequestID)
        REFERENCES LoanRequest (RequestID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (OperationID)
        REFERENCES OperationReceipt (OperationID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (EvaluationID)
        REFERENCES RequestEvaluation (EvaluationID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CHECK (Amount > 0),
    CHECK (CommitmentState IN ('Pending', 'Applied', 'Released')),
    CHECK (
        (CommitmentState = 'Pending' AND AppliedAt IS NULL AND ReleasedAt IS NULL)
        OR (CommitmentState = 'Applied' AND AppliedAt IS NOT NULL AND ReleasedAt IS NULL)
        OR (CommitmentState = 'Released' AND AppliedAt IS NULL AND ReleasedAt IS NOT NULL)
    )
) ENGINE = InnoDB;

-- FR-14–22: one loan per request; borrower and terms are read through that request.
CREATE TABLE Loan (
    LoanID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    RequestID BIGINT UNSIGNED NOT NULL,
    ActivatedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    LoanState VARCHAR(8) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'Active',
    CompletedAt DATETIME(6) NULL,
    ObservedCondition VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'Current',
    LastEvaluatedAt DATETIME(6) NOT NULL,

    UNIQUE (RequestID),
    FOREIGN KEY (RequestID)
        REFERENCES LoanRequest (RequestID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CHECK (LoanState IN ('Active', 'Repaid')),
    CHECK ((LoanState = 'Active' AND CompletedAt IS NULL)
           OR (LoanState = 'Repaid' AND CompletedAt IS NOT NULL)),
    CHECK (ObservedCondition IN ('Current', 'Delinquent'))
) ENGINE = InnoDB;

-- FR-15/18/19: weak entity; installment numbers are unique only within a loan.
CREATE TABLE Installment (
    LoanID BIGINT UNSIGNED NOT NULL,
    InstallmentNumber SMALLINT UNSIGNED NOT NULL,
    DueDate DATE NOT NULL,
    ScheduledPrincipal DECIMAL(18,2) NOT NULL,

    PRIMARY KEY (LoanID, InstallmentNumber),
    UNIQUE (LoanID, DueDate),
    FOREIGN KEY (LoanID)
        REFERENCES Loan (LoanID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CHECK (InstallmentNumber > 0),
    CHECK (ScheduledPrincipal > 0)
) ENGINE = InnoDB;

-- FR-17–21/30: a payment is identified by its loan and local repayment number.
CREATE TABLE Repayment (
    LoanID BIGINT UNSIGNED NOT NULL,
    RepaymentNumber INT UNSIGNED NOT NULL,
    OperationID BIGINT UNSIGNED NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    PostedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),

    PRIMARY KEY (LoanID, RepaymentNumber),
    UNIQUE (OperationID),
    FOREIGN KEY (LoanID)
        REFERENCES Loan (LoanID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (OperationID)
        REFERENCES OperationReceipt (OperationID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CHECK (RepaymentNumber > 0),
    CHECK (Amount > 0)
) ENGINE = InnoDB;

-- FR-18: shared LoanID in both composite foreign keys prevents cross-loan allocation.
CREATE TABLE RepaymentAllocation (
    LoanID BIGINT UNSIGNED NOT NULL,
    RepaymentNumber INT UNSIGNED NOT NULL,
    InstallmentNumber SMALLINT UNSIGNED NOT NULL,
    AllocatedPrincipal DECIMAL(18,2) NOT NULL,

    PRIMARY KEY (LoanID, RepaymentNumber, InstallmentNumber),
    FOREIGN KEY (LoanID, RepaymentNumber)
        REFERENCES Repayment (LoanID, RepaymentNumber) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (LoanID, InstallmentNumber)
        REFERENCES Installment (LoanID, InstallmentNumber) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CHECK (AllocatedPrincipal > 0)
) ENGINE = InnoDB;

-- FR-23: a note targets a request OR a loan. Correction-target checks need a routine.
CREATE TABLE OversightNote (
    NoteID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    RequestID BIGINT UNSIGNED NULL,
    LoanID BIGINT UNSIGNED NULL,
    AdministratorID BIGINT UNSIGNED NOT NULL,
    CreatedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    NoteText TEXT NOT NULL,
    CorrectsNoteID BIGINT UNSIGNED NULL,

    FOREIGN KEY (RequestID)
        REFERENCES LoanRequest (RequestID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (LoanID)
        REFERENCES Loan (LoanID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (AdministratorID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (CorrectsNoteID)
        REFERENCES OversightNote (NoteID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CHECK ((RequestID IS NOT NULL AND LoanID IS NULL)
           OR (RequestID IS NULL AND LoanID IS NOT NULL)),
    CHECK (CHAR_LENGTH(TRIM(NoteText)) > 0)
) ENGINE = InnoDB;

-- FR-28: audit rows store bounded context; trusted append-only writes need routines/grants.
CREATE TABLE AuditEvent (
    AuditEventID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    OccurredAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    EventType VARCHAR(40) COLLATE utf8mb4_0900_bin NOT NULL,
    Outcome VARCHAR(12) COLLATE utf8mb4_0900_bin NOT NULL,
    ActorUserID BIGINT UNSIGNED NULL,
    ActingRoleCode VARCHAR(16) COLLATE utf8mb4_0900_bin NULL,
    ServiceActor VARCHAR(24) COLLATE utf8mb4_0900_bin NULL,
    InitiatingUserID BIGINT UNSIGNED NULL,
    TechnicalAccount VARCHAR(288) NOT NULL,
    SubjectType VARCHAR(32) COLLATE utf8mb4_0900_bin NOT NULL,
    SubjectKey VARCHAR(128) COLLATE utf8mb4_0900_bin NOT NULL,
    ContextID BINARY(16) NOT NULL,
    OperationID BIGINT UNSIGNED NULL,
    AttemptedOperationReference VARCHAR(64) COLLATE utf8mb4_0900_bin NULL,
    ReasonCode VARCHAR(40) COLLATE utf8mb4_0900_bin NULL,

    FOREIGN KEY (ActorUserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (ActingRoleCode)
        REFERENCES `Role` (RoleCode) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (InitiatingUserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (OperationID)
        REFERENCES OperationReceipt (OperationID) ON DELETE RESTRICT ON UPDATE RESTRICT,

    -- Keep basic values valid; event/actor/subject matching is future audit-operation logic.
    CHECK (CHAR_LENGTH(TRIM(TechnicalAccount)) > 0),
    CHECK (CHAR_LENGTH(TRIM(SubjectKey)) > 0),
    CHECK (AttemptedOperationReference IS NULL
           OR CHAR_LENGTH(TRIM(AttemptedOperationReference)) > 0),
    CHECK (EventType IN (
        'UserCreated', 'AccountStatusChanged', 'RoleGranted', 'RoleRevoked', 'ProfileSaved',
        'RequestSaved', 'RequestSubmitted', 'AssessmentCompleted', 'ReviewApproved',
        'ReviewRejected', 'CommitmentAccepted', 'CommitmentApplied', 'LoanActivated',
        'RequestCancelled', 'RequestExpired', 'CommitmentReleased', 'RepaymentPosted',
        'LoanCompleted', 'DelinquencyChanged', 'NoteAppended', 'AttemptRejected',
        'TransactionFailed', 'InterruptionObserved'
    )),
    CHECK (Outcome IN ('Success', 'Denied', 'Failed', 'Interrupted')),
    CHECK (SubjectType IN ('User', 'UserRole', 'BorrowerProfile', 'LoanRequest', 'RequestEvaluation', 'FundingCommitment', 'Loan', 'Repayment', 'OversightNote', 'Attempt')),
    CHECK (ServiceActor IS NULL OR ServiceActor IN (
        'Bootstrap', 'Assessment', 'Activation', 'Release', 'Expiration', 'RepaymentCompletion',
        'Delinquency', 'Recovery'
    )),
    CHECK (ReasonCode IS NULL OR ReasonCode IN (
        'NOT_AUTHENTICATED', 'ROLE_REQUIRED', 'OWNER_REQUIRED', 'PARTICIPATION_REQUIRED',
        'ACCOUNT_RESTRICTED', 'ACCOUNT_INACTIVE', 'ROLE_CONFLICT', 'LIVE_PARTICIPATION',
        'STALE_VERSION', 'DUPLICATE_LOGIN', 'DUPLICATE_ROLE', 'INVALID_INPUT', 'INVALID_STATE',
        'POLICY_LIMIT', 'DEADLINE_REACHED', 'SELF_FUNDING', 'CAPACITY_EXCEEDED', 'OVERPAYMENT',
        'OPERATION_CONFLICT', 'CIPHER_INVALID', 'AFFORDABILITY_FAIL', 'DELINQUENCY_PRESENT',
        'DB_DEADLOCK', 'DB_LOCK_TIMEOUT', 'DB_ERROR', 'CONNECTION_LOST', 'ADMIN_DECISION',
        'BORROWER_CANCELLED', 'WORKER_EXPIRED', 'INTEGRITY_FAILURE', 'UNKNOWN_TARGET'
    )),
    CONSTRAINT chk_audit_failure_reason CHECK (
        Outcome = 'Success' OR ReasonCode IS NOT NULL
    )
) ENGINE = InnoDB;

-- FR-28 / SEC-12: one safe changed field per event; private values stay out of the feed.
CREATE TABLE AuditChange (
    AuditEventID BIGINT UNSIGNED NOT NULL,
    FieldName VARCHAR(64) COLLATE utf8mb4_0900_bin NOT NULL,
    OldValue VARCHAR(1000) NULL,
    NewValue VARCHAR(1000) NULL,

    PRIMARY KEY (AuditEventID, FieldName),
    FOREIGN KEY (AuditEventID)
        REFERENCES AuditEvent (AuditEventID) ON DELETE RESTRICT ON UPDATE RESTRICT,

    CHECK (FieldName IN (
        'AccountStatus', 'ActivatedAt', 'AffordabilityPass', 'AllocationCount', 'Amount',
        'AppliedAt', 'CommitmentState', 'CompletedAt', 'CorrectsNoteID', 'DecidedAt', 'Decision',
        'EvaluationID', 'ExternalObligationsCipher', 'FundingDeadlineAt', 'GrantedAt',
        'InstallmentCount', 'LastEvaluatedAt', 'LoanID', 'LoanState', 'LoginName',
        'MonthlyIncomeCipher', 'NoDelinquencyPass', 'ObservedCondition', 'OldestOverdueDueDate',
        'OutstandingAfter', 'OutstandingBefore', 'OverduePrincipal', 'PasswordHash',
        'PendingTotal', 'PolicyCode', 'Principal', 'PrivateEmailCipher', 'PublicAlias',
        'Purpose', 'ReleasedAt', 'RequestID', 'RequestState', 'Result', 'RevokedAt', 'RoleCode',
        'StatusReason', 'SubmittedAt', 'SubmittedIncomeCipher', 'SubmittedObligationsCipher',
        'TerminalReason', 'UserID'
    )),

    CONSTRAINT chk_audit_private_values CHECK (
        FieldName NOT IN (
            'PrivateEmailCipher', 'PasswordHash', 'MonthlyIncomeCipher',
            'ExternalObligationsCipher', 'SubmittedIncomeCipher',
            'SubmittedObligationsCipher', 'PlatformBurdenCipher'
        )
        OR (OldValue IS NULL AND NewValue IS NULL)
    ),

    CONSTRAINT chk_audit_status_reason CHECK (
        FieldName <> 'StatusReason'
        OR (OldValue IS NULL AND NewValue IS NOT NULL
            AND CHAR_LENGTH(TRIM(NewValue)) > 0
            AND CHAR_LENGTH(NewValue) = CHAR_LENGTH(TRIM(NewValue)))
    )
) ENGINE = InnoDB;
