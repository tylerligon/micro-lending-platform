-- Controlled account/profile/request operations (FR-01/02/03/05/06/07).
-- The future trusted caller supplies authenticated identity and validated encryption.
-- Helpers do not commit. Public actions own their transaction, except submission:
-- prepare starts it; finish commits it on the SAME connection. Never nest transactions.
DELIMITER //

-- Internal helper: lock Administrator/target User rows in ascending ID order.
CREATE PROCEDURE sp_lock_users(IN p_First BIGINT UNSIGNED, IN p_Second BIGINT UNSIGNED)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_ID BIGINT UNSIGNED DEFAULT NULL;
    IF p_First IS NULL OR p_Second IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User IDs are required';
    END IF;
    SELECT UserID INTO v_ID FROM `User` WHERE UserID = LEAST(p_First, p_Second) FOR UPDATE;
    IF v_ID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User does not exist';
    END IF;
    SET v_ID = NULL;
    SELECT UserID INTO v_ID FROM `User` WHERE UserID = GREATEST(p_First, p_Second) FOR UPDATE;
    IF v_ID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User does not exist';
    END IF;
END //

-- Internal helper: check current account eligibility and role while holding locks.
CREATE PROCEDURE sp_require_role(IN p_UserID BIGINT UNSIGNED,
    IN p_Role VARCHAR(16), IN p_AllowRestricted BOOLEAN)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_Status VARCHAR(16) DEFAULT NULL;
    DECLARE v_RoleID BIGINT UNSIGNED DEFAULT NULL;
    SELECT AccountStatus INTO v_Status FROM `User` WHERE UserID = p_UserID FOR UPDATE;
    IF v_Status IS NULL OR v_Status = 'Inactive'
       OR (v_Status = 'Restricted' AND NOT p_AllowRestricted) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account is not eligible for this action';
    END IF;
    SELECT UserRoleID INTO v_RoleID FROM UserRole
    WHERE UserID = p_UserID AND RoleCode = p_Role AND ActiveMarker = 1 FOR UPDATE;
    IF v_RoleID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Required active role is missing';
    END IF;
END //

-- Internal helper: do not strand live requests, commitments or loans (BR-03).
CREATE PROCEDURE sp_require_no_live_participation(IN p_UserID BIGINT UNSIGNED)
SQL SECURITY INVOKER
BEGIN
    IF EXISTS (SELECT 1 FROM LoanRequest WHERE BorrowerID = p_UserID
        AND RequestState IN ('Submitted', 'PendingReview', 'OpenFunding'))
       OR EXISTS (SELECT 1 FROM FundingCommitment c JOIN OperationReceipt o
            ON o.OperationID = c.OperationID
            WHERE o.CallerUserID = p_UserID AND c.CommitmentState = 'Pending')
       OR EXISTS (SELECT 1 FROM Loan l JOIN LoanRequest r ON r.RequestID = l.RequestID
            WHERE l.LoanState = 'Active' AND (r.BorrowerID = p_UserID
                OR EXISTS (SELECT 1 FROM FundingCommitment c JOIN OperationReceipt o
                    ON o.OperationID = c.OperationID WHERE c.RequestID = r.RequestID
                    AND c.CommitmentState = 'Applied' AND o.CallerUserID = p_UserID))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Live participation prevents deactivation or lending-role removal';
    END IF;
END //

-- Internal helper: append a narrowly scoped human success audit.
CREATE PROCEDURE sp_early_audit(IN p_Event VARCHAR(40), IN p_Actor BIGINT UNSIGNED,
    IN p_Role VARCHAR(16), IN p_Subject VARCHAR(32), IN p_Key BIGINT UNSIGNED,
    IN p_Context BINARY(16), OUT p_AuditID BIGINT UNSIGNED)
SQL SECURITY INVOKER
BEGIN
    IF NOT ((BINARY p_Role = 'Administrator' AND
             ((p_Event IN ('UserCreated', 'AccountStatusChanged') AND p_Subject = 'User')
              OR (p_Event IN ('RoleGranted', 'RoleRevoked') AND p_Subject = 'UserRole')))
        OR (BINARY p_Role = 'Borrower' AND
             ((p_Event = 'ProfileSaved' AND p_Subject = 'BorrowerProfile')
              OR (p_Event IN ('RequestSaved', 'RequestSubmitted') AND p_Subject = 'LoanRequest'))))
        OR p_Actor IS NULL OR p_Key IS NULL OR p_Context IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid early-workflow audit context';
    END IF;
    INSERT INTO AuditEvent (EventType, Outcome, ActorUserID, ActingRoleCode,
        TechnicalAccount, SubjectType, SubjectKey, ContextID, ReasonCode)
    VALUES (p_Event, 'Success', p_Actor, p_Role, SESSION_USER(), p_Subject,
        CAST(p_Key AS CHAR), p_Context,
        IF(p_Event = 'AccountStatusChanged', 'ADMIN_DECISION', NULL));
    SET p_AuditID = LAST_INSERT_ID();
END //

-- Internal helper: calculate current burden and delinquency under the borrower lock.
CREATE PROCEDURE sp_submission_exposure(IN p_BorrowerID BIGINT UNSIGNED,
    IN p_RequestID BIGINT UNSIGNED, IN p_AsOf DATETIME(6),
    OUT p_Burden DECIMAL(18,2), OUT p_NoDelinquency BOOLEAN)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_RequestBurden DECIMAL(18,2);
    DECLARE v_LoanBurden DECIMAL(18,2);
    -- Largest proposed installment: the last carries the rounding remainder.
    SELECT COALESCE(SUM(Principal - FLOOR(Principal * 100 / InstallmentCount)
        * (InstallmentCount - 1) / 100), 0) INTO v_RequestBurden
    FROM LoanRequest WHERE BorrowerID = p_BorrowerID AND RequestID <> p_RequestID
        AND RequestState IN ('Submitted', 'PendingReview', 'OpenFunding')
        AND NOT EXISTS (SELECT 1 FROM Loan WHERE Loan.RequestID = LoanRequest.RequestID);
    SELECT COALESCE(SUM(x.LargestRemaining), 0) INTO v_LoanBurden
    FROM (SELECT l.LoanID, MAX(i.RemainingPrincipal) AS LargestRemaining
        FROM Loan l JOIN LoanRequest r ON r.RequestID = l.RequestID
        JOIN v_installment_remaining i ON i.LoanID = l.LoanID
        WHERE r.BorrowerID = p_BorrowerID AND l.LoanState = 'Active'
        GROUP BY l.LoanID) x;
    IF EXISTS (SELECT 1 FROM v_installment_remaining i JOIN Loan l ON l.LoanID = i.LoanID
        JOIN LoanRequest r ON r.RequestID = l.RequestID
        WHERE r.BorrowerID = p_BorrowerID AND l.LoanState = 'Active'
        AND i.RemainingPrincipal < 0) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Installment allocation integrity failure';
    END IF;
    SET p_Burden = v_RequestBurden + v_LoanBurden;
    SET p_NoDelinquency = NOT EXISTS (
        SELECT 1 FROM v_installment_remaining i JOIN Loan l ON l.LoanID = i.LoanID
        JOIN LoanRequest r ON r.RequestID = l.RequestID
        WHERE r.BorrowerID = p_BorrowerID AND l.LoanState = 'Active'
        AND i.DueDate < DATE(p_AsOf) AND i.RemainingPrincipal > 0);
END //

-- FR-06: create an owned Draft and its audit atomically.
CREATE PROCEDURE sp_create_loan_request (
    IN p_BorrowerID BIGINT UNSIGNED,
    IN p_Purpose TEXT,
    IN p_Principal TEXT,
    IN p_InstallmentCount INT
)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_Principal DECIMAL(18,2);
    DECLARE v_AccountStatus VARCHAR(16) DEFAULT NULL;
    DECLARE v_UserRoleID BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_ProfileUserID BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_RequestID BIGINT UNSIGNED;
    DECLARE v_AuditEventID BIGINT UNSIGNED;

    -- Any SQL error, including our SIGNAL messages, undoes all writes and is returned.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;

    IF p_BorrowerID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Borrower ID is required';
    END IF;
    IF p_Purpose IS NULL OR CHAR_LENGTH(TRIM(p_Purpose)) = 0
       OR CHAR_LENGTH(p_Purpose) > 1000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Purpose must contain 1 to 1000 characters';
    END IF;
    SET v_Principal = fn_money(p_Principal);
    IF v_Principal < 100.00 OR v_Principal > 2000.00 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Principal must be between 100.00 and 2000.00';
    END IF;
    IF p_InstallmentCount IS NULL OR p_InstallmentCount NOT IN (3, 6) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Installment count must be 3 or 6';
    END IF;

    -- Lock the account, active role assignment, and profile until commit/rollback.
    SELECT AccountStatus INTO v_AccountStatus
    FROM `User` WHERE UserID = p_BorrowerID FOR UPDATE;
    IF v_AccountStatus IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Borrower does not exist';
    END IF;
    IF v_AccountStatus <> 'Active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Borrower account must be Active';
    END IF;

    SELECT UserRoleID INTO v_UserRoleID
    FROM UserRole
    WHERE UserID = p_BorrowerID AND RoleCode = 'Borrower' AND ActiveMarker = 1
    FOR UPDATE;
    IF v_UserRoleID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Active Borrower role is required';
    END IF;

    SELECT UserID INTO v_ProfileUserID
    FROM BorrowerProfile WHERE UserID = p_BorrowerID FOR UPDATE;
    IF v_ProfileUserID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Borrower profile is required';
    END IF;

    -- Submission fields remain NULL. The new request starts as Draft, version 0.
    INSERT INTO LoanRequest (BorrowerID, Purpose, Principal, InstallmentCount)
    VALUES (p_BorrowerID, TRIM(p_Purpose), v_Principal, p_InstallmentCount);
    SET v_RequestID = LAST_INSERT_ID();

    -- The successful action and its safe audit details commit together.
    INSERT INTO AuditEvent (EventType, Outcome, ActorUserID, ActingRoleCode,
        TechnicalAccount, SubjectType, SubjectKey, ContextID)
    VALUES ('RequestSaved', 'Success', p_BorrowerID, 'Borrower', SESSION_USER(),
            'LoanRequest', CAST(v_RequestID AS CHAR), UUID_TO_BIN(UUID()));
    SET v_AuditEventID = LAST_INSERT_ID();

    INSERT INTO AuditChange (AuditEventID, FieldName, OldValue, NewValue) VALUES
        (v_AuditEventID, 'Purpose', NULL, TRIM(p_Purpose)),
        (v_AuditEventID, 'Principal', NULL, CAST(v_Principal AS CHAR)),
        (v_AuditEventID, 'InstallmentCount', NULL, CAST(p_InstallmentCount AS CHAR)),
        (v_AuditEventID, 'RequestState', NULL, 'Draft');

    COMMIT;
    SELECT v_RequestID AS RequestID, 'Draft' AS RequestState, 0 AS RowVersion;
END //

-- FR-01: an Active Administrator creates an account; bootstrap is separate.
CREATE PROCEDURE sp_create_user(IN p_AdminID BIGINT UNSIGNED,
    IN p_LoginName TEXT, IN p_DisplayName TEXT, IN p_PublicAlias TEXT,
    IN p_EmailCipher BLOB, IN p_PasswordHash TEXT)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_UserID BIGINT UNSIGNED;
    DECLARE v_AuditID BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    CALL sp_require_role(p_AdminID, 'Administrator', FALSE);
    IF p_LoginName IS NULL OR CHAR_LENGTH(TRIM(p_LoginName)) = 0 OR CHAR_LENGTH(p_LoginName) > 80
       OR p_DisplayName IS NULL OR CHAR_LENGTH(TRIM(p_DisplayName)) = 0 OR CHAR_LENGTH(p_DisplayName) > 120
       OR p_PublicAlias IS NULL OR CHAR_LENGTH(TRIM(p_PublicAlias)) = 0 OR CHAR_LENGTH(p_PublicAlias) > 40
       OR p_EmailCipher IS NULL OR OCTET_LENGTH(p_EmailCipher) NOT BETWEEN 1 AND 512
       OR p_PasswordHash IS NULL OR CHAR_LENGTH(TRIM(p_PasswordHash)) = 0 OR CHAR_LENGTH(p_PasswordHash) > 255 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Valid identity, email envelope and password hash are required';
    END IF;
    INSERT INTO `User` (LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
    VALUES (TRIM(p_LoginName), TRIM(p_DisplayName), TRIM(p_PublicAlias), p_EmailCipher, p_PasswordHash);
    SET v_UserID = LAST_INSERT_ID();
    CALL sp_early_audit('UserCreated', p_AdminID, 'Administrator', 'User', v_UserID,
        UUID_TO_BIN(UUID()), v_AuditID);
    INSERT INTO AuditChange (AuditEventID, FieldName, NewValue) VALUES
        (v_AuditID, 'LoginName', TRIM(p_LoginName)),
        (v_AuditID, 'PublicAlias', TRIM(p_PublicAlias)), (v_AuditID, 'AccountStatus', 'Active'),
        (v_AuditID, 'PrivateEmailCipher', NULL), (v_AuditID, 'PasswordHash', NULL);
    COMMIT;
    SELECT v_UserID AS UserID, 'Active' AS AccountStatus, 0 AS RowVersion;
END //

-- FR-02: grant a new role episode or revoke the current one, preserving history.
CREATE PROCEDURE sp_set_role(IN p_AdminID BIGINT UNSIGNED, IN p_UserID BIGINT UNSIGNED,
    IN p_RoleCode TEXT, IN p_Grant BOOLEAN)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_RoleID BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_AuditID BIGINT UNSIGNED;
    DECLARE v_Time DATETIME(6);
    DECLARE v_Status VARCHAR(16);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    CALL sp_lock_users(p_AdminID, p_UserID);
    CALL sp_require_role(p_AdminID, 'Administrator', FALSE);
    IF p_RoleCode IS NULL OR BINARY p_RoleCode NOT IN ('Borrower', 'Lender', 'Administrator', 'Auditor')
       OR p_Grant IS NULL OR p_Grant NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Canonical role and grant flag 0 or 1 are required';
    END IF;
    SELECT AccountStatus INTO v_Status FROM `User` WHERE UserID = p_UserID;
    SELECT UserRoleID INTO v_RoleID FROM UserRole
    WHERE UserID = p_UserID AND RoleCode = p_RoleCode AND ActiveMarker = 1 FOR UPDATE;
    SET v_Time = UTC_TIMESTAMP(6);
    IF p_Grant = 1 THEN
        IF v_Status = 'Inactive' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot grant a role to an Inactive account';
        END IF;
        IF v_RoleID IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Role is already active';
        END IF;
        IF EXISTS (SELECT 1 FROM UserRole WHERE UserID = p_UserID AND ActiveMarker = 1
            AND ((p_RoleCode IN ('Borrower', 'Lender') AND RoleCode IN ('Administrator', 'Auditor'))
                OR (p_RoleCode IN ('Administrator', 'Auditor')))) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Role conflicts with existing participation or oversight role';
        END IF;
        INSERT INTO UserRole (UserID, RoleCode, GrantedAt, GrantedByUserID)
        VALUES (p_UserID, p_RoleCode, v_Time, p_AdminID);
        SET v_RoleID = LAST_INSERT_ID();
        CALL sp_early_audit('RoleGranted', p_AdminID, 'Administrator', 'UserRole', v_RoleID,
            UUID_TO_BIN(UUID()), v_AuditID);
        INSERT INTO AuditChange (AuditEventID, FieldName, NewValue) VALUES
            (v_AuditID, 'UserID', CAST(p_UserID AS CHAR)), (v_AuditID, 'RoleCode', p_RoleCode),
            (v_AuditID, 'GrantedAt', CAST(v_Time AS CHAR));
    ELSE
        IF v_RoleID IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Role is not active';
        END IF;
        IF p_RoleCode IN ('Borrower', 'Lender') THEN
            CALL sp_require_no_live_participation(p_UserID);
        END IF;
        -- Audit first, while the administrator's own role is still effective.
        CALL sp_early_audit('RoleRevoked', p_AdminID, 'Administrator', 'UserRole', v_RoleID,
            UUID_TO_BIN(UUID()), v_AuditID);
        SELECT GREATEST(UTC_TIMESTAMP(6), DATE_ADD(OccurredAt, INTERVAL 1 MICROSECOND))
            INTO v_Time FROM AuditEvent WHERE AuditEventID = v_AuditID;
        INSERT INTO AuditChange (AuditEventID, FieldName, NewValue)
        VALUES (v_AuditID, 'RevokedAt', CAST(v_Time AS CHAR));
        UPDATE UserRole SET RevokedAt = v_Time, RevokedByUserID = p_AdminID WHERE UserRoleID = v_RoleID;
    END IF;
    UPDATE `User` SET RowVersion = RowVersion + 1 WHERE UserID = p_UserID;
    COMMIT;
    SELECT v_RoleID AS UserRoleID, p_Grant AS IsActive;
END //

-- FR-03: change account status with a reason and expected version.
CREATE PROCEDURE sp_set_account_status(IN p_AdminID BIGINT UNSIGNED,
    IN p_UserID BIGINT UNSIGNED, IN p_ExpectedVersion BIGINT UNSIGNED,
    IN p_Status TEXT, IN p_Reason TEXT)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_OldStatus VARCHAR(16);
    DECLARE v_Version BIGINT UNSIGNED;
    DECLARE v_AuditID BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    CALL sp_lock_users(p_AdminID, p_UserID);
    CALL sp_require_role(p_AdminID, 'Administrator', FALSE);
    SELECT AccountStatus, RowVersion INTO v_OldStatus, v_Version FROM `User` WHERE UserID = p_UserID;
    IF p_ExpectedVersion IS NULL OR p_ExpectedVersion <> v_Version THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stale account version';
    END IF;
    IF p_Status IS NULL OR BINARY p_Status NOT IN ('Active', 'Restricted', 'Inactive')
       OR p_Reason IS NULL OR CHAR_LENGTH(TRIM(p_Reason)) = 0 OR CHAR_LENGTH(p_Reason) > 1000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Canonical status and a nonblank reason are required';
    END IF;
    IF BINARY p_Status = BINARY v_OldStatus THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account already has this status';
    END IF;
    IF BINARY p_Status = 'Inactive' THEN
        CALL sp_require_no_live_participation(p_UserID);
    END IF;
    CALL sp_early_audit('AccountStatusChanged', p_AdminID, 'Administrator', 'User', p_UserID,
        UUID_TO_BIN(UUID()), v_AuditID);
    INSERT INTO AuditChange (AuditEventID, FieldName, OldValue, NewValue) VALUES
        (v_AuditID, 'AccountStatus', v_OldStatus, p_Status),
        (v_AuditID, 'StatusReason', NULL, TRIM(p_Reason));
    UPDATE `User` SET AccountStatus = p_Status, RowVersion = RowVersion + 1 WHERE UserID = p_UserID;
    COMMIT;
    SELECT p_UserID AS UserID, p_Status AS AccountStatus, v_Version + 1 AS RowVersion;
END //

-- FR-05: create/update the owning Borrower profile; Restricted is permitted.
CREATE PROCEDURE sp_save_profile(IN p_BorrowerID BIGINT UNSIGNED,
    IN p_ExpectedVersion BIGINT UNSIGNED, IN p_Income TEXT, IN p_Obligations TEXT,
    IN p_IncomeCipher BLOB, IN p_ObligationsCipher BLOB)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_Version BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_Income DECIMAL(18,2);
    DECLARE v_Obligations DECIMAL(18,2);
    DECLARE v_AuditID BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    -- Restricted borrowers may still maintain their own profile (BR-03).
    CALL sp_require_role(p_BorrowerID, 'Borrower', TRUE);
    SET v_Income = fn_money(p_Income);
    SET v_Obligations = fn_money(p_Obligations);
    IF v_Income <= 0 OR p_IncomeCipher IS NULL OR OCTET_LENGTH(p_IncomeCipher) NOT BETWEEN 1 AND 128
       OR p_ObligationsCipher IS NULL OR OCTET_LENGTH(p_ObligationsCipher) NOT BETWEEN 1 AND 128 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Positive income and nonempty financial envelopes are required';
    END IF;
    SELECT RowVersion INTO v_Version FROM BorrowerProfile WHERE UserID = p_BorrowerID FOR UPDATE;
    IF v_Version IS NULL THEN
        IF p_ExpectedVersion IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'New profile requires NULL expected version';
        END IF;
        INSERT INTO BorrowerProfile (UserID, MonthlyIncomeCipher, ExternalObligationsCipher)
        VALUES (p_BorrowerID, p_IncomeCipher, p_ObligationsCipher);
        SET v_Version = 0;
    ELSE
        IF p_ExpectedVersion IS NULL OR p_ExpectedVersion <> v_Version THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stale profile version';
        END IF;
        SET v_Version = v_Version + 1;
        UPDATE BorrowerProfile SET MonthlyIncomeCipher = p_IncomeCipher,
            ExternalObligationsCipher = p_ObligationsCipher, UpdatedAt = UTC_TIMESTAMP(6),
            RowVersion = v_Version WHERE UserID = p_BorrowerID;
    END IF;
    CALL sp_early_audit('ProfileSaved', p_BorrowerID, 'Borrower', 'BorrowerProfile', p_BorrowerID,
        UUID_TO_BIN(UUID()), v_AuditID);
    -- Field names only. Never put private plaintext, ciphertext or hashes in the audit feed.
    INSERT INTO AuditChange (AuditEventID, FieldName) VALUES
        (v_AuditID, 'MonthlyIncomeCipher'), (v_AuditID, 'ExternalObligationsCipher');
    COMMIT;
    SELECT p_BorrowerID AS UserID, v_Version AS RowVersion;
END //

-- FR-06: an Active Borrower edits their owned Draft at the expected version.
CREATE PROCEDURE sp_update_loan_request(IN p_BorrowerID BIGINT UNSIGNED,
    IN p_RequestID BIGINT UNSIGNED, IN p_ExpectedVersion BIGINT UNSIGNED,
    IN p_Purpose TEXT, IN p_Principal TEXT, IN p_InstallmentCount INT)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_Owner BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_State VARCHAR(20);
    DECLARE v_Version BIGINT UNSIGNED;
    DECLARE v_Purpose VARCHAR(1000);
    DECLARE v_Principal DECIMAL(18,2);
    DECLARE v_NewPrincipal DECIMAL(18,2);
    DECLARE v_Term INT;
    DECLARE v_AuditID BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    CALL sp_require_role(p_BorrowerID, 'Borrower', FALSE);
    IF NOT EXISTS (SELECT 1 FROM BorrowerProfile WHERE UserID = p_BorrowerID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Borrower profile is required';
    END IF;
    SELECT BorrowerID, RequestState, RowVersion, Purpose, Principal, InstallmentCount
        INTO v_Owner, v_State, v_Version, v_Purpose, v_Principal, v_Term
    FROM LoanRequest WHERE RequestID = p_RequestID FOR UPDATE;
    IF v_Owner IS NULL OR v_Owner <> p_BorrowerID THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Owned request is required';
    END IF;
    IF v_State <> 'Draft' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only Draft requests may be edited';
    END IF;
    IF p_ExpectedVersion IS NULL OR p_ExpectedVersion <> v_Version THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stale request version';
    END IF;
    SET v_NewPrincipal = fn_money(p_Principal);
    IF p_Purpose IS NULL OR CHAR_LENGTH(TRIM(p_Purpose)) = 0 OR CHAR_LENGTH(p_Purpose) > 1000
       OR v_NewPrincipal NOT BETWEEN 100 AND 2000
       OR p_InstallmentCount IS NULL OR p_InstallmentCount NOT IN (3, 6) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Valid purpose, principal 100 to 2000, and term 3 or 6 are required';
    END IF;
    UPDATE LoanRequest SET Purpose = TRIM(p_Purpose), Principal = v_NewPrincipal,
        InstallmentCount = p_InstallmentCount, RowVersion = RowVersion + 1 WHERE RequestID = p_RequestID;
    CALL sp_early_audit('RequestSaved', p_BorrowerID, 'Borrower', 'LoanRequest', p_RequestID,
        UUID_TO_BIN(UUID()), v_AuditID);
    INSERT INTO AuditChange (AuditEventID, FieldName, OldValue, NewValue) VALUES
        (v_AuditID, 'Purpose', v_Purpose, TRIM(p_Purpose)),
        (v_AuditID, 'Principal', CAST(v_Principal AS CHAR), CAST(v_NewPrincipal AS CHAR)),
        (v_AuditID, 'InstallmentCount', CAST(v_Term AS CHAR), CAST(p_InstallmentCount AS CHAR));
    COMMIT;
    SELECT p_RequestID AS RequestID, 'Draft' AS RequestState, v_Version + 1 AS RowVersion;
END //

-- Internal helper: clear connection-local submission preparation context.
CREATE PROCEDURE sp_clear_submission()
SQL SECURITY INVOKER
BEGIN
    SET @ml_submit_user = NULL, @ml_submit_request = NULL, @ml_submit_context = NULL,
        @ml_submit_profile_version = NULL, @ml_submit_request_version = NULL,
        @ml_submit_income_digest = NULL, @ml_submit_obligations_digest = NULL,
        @ml_submit_time = NULL, @ml_submit_burden = NULL, @ml_submit_no_delinquency = NULL;
END //

-- FR-07 prepare: start transaction, lock source records, retain context and SAVEPOINT.
CREATE PROCEDURE sp_prepare_submission(IN p_BorrowerID BIGINT UNSIGNED,
    IN p_RequestID BIGINT UNSIGNED, IN p_ExpectedVersion BIGINT UNSIGNED)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_Owner BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_State VARCHAR(20);
    DECLARE v_Version BIGINT UNSIGNED;
    DECLARE v_ProfileVersion BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_Income VARBINARY(128);
    DECLARE v_Obligations VARBINARY(128);
    DECLARE v_Time DATETIME(6);
    DECLARE v_Burden DECIMAL(18,2);
    DECLARE v_NoDelinquency BOOLEAN;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; CALL sp_clear_submission(); RESIGNAL; END;
    CALL sp_clear_submission();
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    CALL sp_require_role(p_BorrowerID, 'Borrower', FALSE);
    SELECT RowVersion, MonthlyIncomeCipher, ExternalObligationsCipher
        INTO v_ProfileVersion, v_Income, v_Obligations
    FROM BorrowerProfile WHERE UserID = p_BorrowerID FOR UPDATE;
    IF v_ProfileVersion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Borrower profile is required';
    END IF;
    SELECT BorrowerID, RequestState, RowVersion INTO v_Owner, v_State, v_Version
    FROM LoanRequest WHERE RequestID = p_RequestID FOR UPDATE;
    IF v_Owner IS NULL OR v_Owner <> p_BorrowerID THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Owned request is required';
    END IF;
    IF v_State <> 'Draft' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only Draft requests may be submitted';
    END IF;
    IF p_ExpectedVersion IS NULL OR p_ExpectedVersion <> v_Version THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stale request version';
    END IF;
    SET v_Time = UTC_TIMESTAMP(6);
    CALL sp_submission_exposure(p_BorrowerID, p_RequestID, v_Time, v_Burden, v_NoDelinquency);
    SET @ml_submit_user = p_BorrowerID, @ml_submit_request = p_RequestID,
        @ml_submit_context = UUID_TO_BIN(UUID()), @ml_submit_profile_version = v_ProfileVersion,
        @ml_submit_request_version = v_Version, @ml_submit_income_digest = SHA2(v_Income, 256),
        @ml_submit_obligations_digest = SHA2(v_Obligations, 256), @ml_submit_time = v_Time,
        @ml_submit_burden = v_Burden, @ml_submit_no_delinquency = v_NoDelinquency;
    -- This savepoint must still exist at finish: an intervening COMMIT/ROLLBACK loses it.
    SAVEPOINT ml_submission_ready;
    SELECT p_RequestID AS RequestID, v_Version AS RequestVersion,
        v_ProfileVersion AS ProfileVersion, HEX(@ml_submit_context) AS ContextHex,
        v_Time AS SnapshotAt, v_Income AS IncomeCipher, v_Obligations AS ObligationsCipher,
        v_Burden AS PlatformBurden, v_NoDelinquency AS NoDelinquencyPass;
    -- Intentionally no COMMIT: retain borrower/profile/request locks for finish.
END //

-- FR-07 finish: same reserved connection, fresh encrypted snapshots, atomic commit.
CREATE PROCEDURE sp_submit_request(IN p_BorrowerID BIGINT UNSIGNED,
    IN p_RequestID BIGINT UNSIGNED, IN p_Context BLOB,
    IN p_Income TEXT, IN p_Obligations TEXT,
    IN p_SubmittedIncomeCipher BLOB, IN p_SubmittedObligationsCipher BLOB,
    IN p_PlatformBurdenCipher BLOB)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_Income DECIMAL(18,2);
    DECLARE v_Obligations DECIMAL(18,2);
    DECLARE v_EvaluationID BIGINT UNSIGNED;
    DECLARE v_AuditID BIGINT UNSIGNED;
    DECLARE v_Version BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN ROLLBACK; CALL sp_clear_submission(); RESIGNAL; END;
    IF @ml_submit_context IS NULL OR p_Context IS NULL OR OCTET_LENGTH(p_Context) <> 16
       OR NOT (p_Context <=> @ml_submit_context)
       OR p_BorrowerID IS NULL OR NOT (p_BorrowerID <=> @ml_submit_user)
       OR p_RequestID IS NULL OR NOT (p_RequestID <=> @ml_submit_request) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Matching prepared submission on this connection is required';
    END IF;
    RELEASE SAVEPOINT ml_submission_ready;
    CALL sp_require_role(p_BorrowerID, 'Borrower', FALSE);
    -- Guard against changes even from another statement on the reserved connection.
    IF NOT EXISTS (SELECT 1 FROM LoanRequest WHERE RequestID = p_RequestID
        AND BorrowerID = p_BorrowerID AND RequestState = 'Draft'
        AND RowVersion = @ml_submit_request_version)
       OR NOT EXISTS (SELECT 1 FROM BorrowerProfile WHERE UserID = p_BorrowerID
        AND RowVersion = @ml_submit_profile_version
        AND SHA2(MonthlyIncomeCipher, 256) = @ml_submit_income_digest
        AND SHA2(ExternalObligationsCipher, 256) = @ml_submit_obligations_digest) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prepared profile or request has changed';
    END IF;
    -- Values must be authenticated decryptions supplied by the trusted service.
    SET v_Income = fn_money(p_Income);
    SET v_Obligations = fn_money(p_Obligations);
    IF v_Income <= 0 OR p_SubmittedIncomeCipher IS NULL
       OR OCTET_LENGTH(p_SubmittedIncomeCipher) NOT BETWEEN 1 AND 128
       OR p_SubmittedObligationsCipher IS NULL
       OR OCTET_LENGTH(p_SubmittedObligationsCipher) NOT BETWEEN 1 AND 128
       OR p_PlatformBurdenCipher IS NULL OR OCTET_LENGTH(p_PlatformBurdenCipher) NOT BETWEEN 1 AND 128 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Valid financial values and prepared snapshot envelopes are required';
    END IF;
    -- No affordability decision yet: even an unaffordable Draft may be submitted.
    INSERT INTO RequestEvaluation (RequestID, EvaluationKind, AttemptNumber,
        EvaluatedAt, PlatformBurdenCipher, NoDelinquencyPass, ContextID)
    VALUES (p_RequestID, 'Submission', 0, @ml_submit_time, p_PlatformBurdenCipher,
        @ml_submit_no_delinquency, p_Context);
    SET v_EvaluationID = LAST_INSERT_ID();
    SET v_Version = @ml_submit_request_version + 1;
    UPDATE LoanRequest SET RequestState = 'Submitted', PolicyCode = 'D1',
        SubmittedAt = @ml_submit_time, SubmittedIncomeCipher = p_SubmittedIncomeCipher,
        SubmittedObligationsCipher = p_SubmittedObligationsCipher, RowVersion = v_Version
    WHERE RequestID = p_RequestID;
    CALL sp_early_audit('RequestSubmitted', p_BorrowerID, 'Borrower', 'LoanRequest', p_RequestID,
        p_Context, v_AuditID);
    INSERT INTO AuditChange (AuditEventID, FieldName, OldValue, NewValue) VALUES
        (v_AuditID, 'RequestState', 'Draft', 'Submitted'),
        (v_AuditID, 'PolicyCode', NULL, 'D1'),
        (v_AuditID, 'SubmittedAt', NULL, CAST(@ml_submit_time AS CHAR)),
        (v_AuditID, 'EvaluationID', NULL, CAST(v_EvaluationID AS CHAR)),
        (v_AuditID, 'SubmittedIncomeCipher', NULL, NULL),
        (v_AuditID, 'SubmittedObligationsCipher', NULL, NULL);
    COMMIT;
    CALL sp_clear_submission();
    SELECT p_RequestID AS RequestID, 'Submitted' AS RequestState,
        v_Version AS RowVersion, v_EvaluationID AS EvaluationID;
END //

DELIMITER ;
