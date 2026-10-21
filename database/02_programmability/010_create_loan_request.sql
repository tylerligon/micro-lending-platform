-- FR-06: create one Draft request for an eligible borrower.
-- Local demonstration: the future trusted service must supply the authenticated UserID.
-- This procedure owns its transaction. Call it outside any existing transaction.
DELIMITER //

CREATE PROCEDURE sp_create_loan_request (
    IN p_BorrowerID BIGINT UNSIGNED,
    IN p_Purpose TEXT,
    IN p_Principal DECIMAL(18,2),
    IN p_InstallmentCount INT
)
SQL SECURITY INVOKER
BEGIN
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

    START TRANSACTION;

    IF p_BorrowerID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Borrower ID is required';
    END IF;
    IF p_Purpose IS NULL OR CHAR_LENGTH(TRIM(p_Purpose)) = 0
       OR CHAR_LENGTH(p_Purpose) > 1000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Purpose must contain 1 to 1000 characters';
    END IF;
    IF p_Principal IS NULL OR p_Principal < 100.00 OR p_Principal > 2000.00 THEN
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
    VALUES (p_BorrowerID, TRIM(p_Purpose), p_Principal, p_InstallmentCount);
    SET v_RequestID = LAST_INSERT_ID();

    -- The successful action and its safe audit details commit together.
    INSERT INTO AuditEvent (EventType, Outcome, ActorUserID, ActingRoleCode,
        TechnicalAccount, SubjectType, SubjectKey, ContextID)
    VALUES ('RequestSaved', 'Success', p_BorrowerID, 'Borrower', SESSION_USER(),
            'LoanRequest', CAST(v_RequestID AS CHAR), UUID_TO_BIN(UUID()));
    SET v_AuditEventID = LAST_INSERT_ID();

    INSERT INTO AuditChange (AuditEventID, FieldName, OldValue, NewValue) VALUES
        (v_AuditEventID, 'Purpose', NULL, TRIM(p_Purpose)),
        (v_AuditEventID, 'Principal', NULL, CAST(p_Principal AS CHAR)),
        (v_AuditEventID, 'InstallmentCount', NULL, CAST(p_InstallmentCount AS CHAR)),
        (v_AuditEventID, 'RequestState', NULL, 'Draft');

    COMMIT;
    SELECT v_RequestID AS RequestID, 'Draft' AS RequestState, 0 AS RowVersion;
END //

DELIMITER ;
