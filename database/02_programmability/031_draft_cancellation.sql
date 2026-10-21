-- Midterm subset of FR-10: Draft only. No assessment, funding or release workflow.
-- Trusted SQL caller supplies the verified actor ID and chosen current role.
-- Like existing actions, call OUTSIDE an existing transaction: this action commits.
DELIMITER //
CREATE PROCEDURE sp_cancel_draft(IN p_ActorID BIGINT UNSIGNED,
    IN p_ActingRole TEXT, IN p_RequestID BIGINT UNSIGNED,
    IN p_ExpectedVersion BIGINT UNSIGNED, IN p_Reason TEXT)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_Owner BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_State VARCHAR(20);
    DECLARE v_Version BIGINT UNSIGNED;
    DECLARE v_OldReason VARCHAR(1000);
    DECLARE v_AuditID BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    IF p_ActorID IS NULL OR p_RequestID IS NULL OR p_ActingRole IS NULL
       OR BINARY p_ActingRole NOT IN ('Borrower', 'Administrator') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Actor, request and canonical cancellation role are required';
    END IF;
    IF p_Reason IS NULL OR NOT REGEXP_LIKE(p_Reason, '[^[:space:]]') OR CHAR_LENGTH(p_Reason) > 1000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancellation reason must contain 1 to 1000 characters';
    END IF;
    -- Discover the immutable owner before acquiring User locks in ascending ID order.
    SELECT BorrowerID INTO v_Owner FROM LoanRequest WHERE RequestID = p_RequestID;
    IF v_Owner IS NULL OR (BINARY p_ActingRole = 'Borrower' AND v_Owner <> p_ActorID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Owned request or Administrator access is required';
    END IF;
    CALL sp_lock_users(p_ActorID, v_Owner);
    CALL sp_require_role(p_ActorID, p_ActingRole, BINARY p_ActingRole = 'Borrower');
    SELECT RequestState, RowVersion, TerminalReason INTO v_State, v_Version, v_OldReason
    FROM LoanRequest WHERE RequestID = p_RequestID FOR UPDATE;
    IF v_State <> 'Draft' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only Draft cancellation is implemented';
    END IF;
    IF p_ExpectedVersion IS NULL OR p_ExpectedVersion <> v_Version THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stale request version';
    END IF;
    -- Do not silently cancel an inconsistent directly inserted "Draft" with children.
    IF EXISTS (SELECT 1 FROM RequestEvaluation WHERE RequestID = p_RequestID)
       OR EXISTS (SELECT 1 FROM FundingCommitment WHERE RequestID = p_RequestID)
       OR EXISTS (SELECT 1 FROM Loan WHERE RequestID = p_RequestID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Draft has unexpected lending records';
    END IF;
    UPDATE LoanRequest SET RequestState = 'Cancelled', TerminalReason = TRIM(p_Reason),
        RowVersion = RowVersion + 1 WHERE RequestID = p_RequestID;
    INSERT INTO AuditEvent (EventType, Outcome, ActorUserID, ActingRoleCode,
        TechnicalAccount, SubjectType, SubjectKey, ContextID, ReasonCode)
    VALUES ('RequestCancelled', 'Success', p_ActorID, p_ActingRole, SESSION_USER(),
        'LoanRequest', CAST(p_RequestID AS CHAR), UUID_TO_BIN(UUID()),
        IF(BINARY p_ActingRole = 'Administrator', 'ADMIN_DECISION', 'BORROWER_CANCELLED'));
    SET v_AuditID = LAST_INSERT_ID();
    INSERT INTO AuditChange (AuditEventID, FieldName, OldValue, NewValue) VALUES
        (v_AuditID, 'RequestState', 'Draft', 'Cancelled'),
        (v_AuditID, 'TerminalReason', v_OldReason, TRIM(p_Reason));
    COMMIT;
    SELECT p_RequestID AS RequestID, 'Cancelled' AS RequestState, v_Version + 1 AS RowVersion;
END //
DELIMITER ;
