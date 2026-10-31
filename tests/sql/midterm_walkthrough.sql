-- 1
USE micro_lending_midterm_demo;
SET SESSION time_zone = '+00:00';
SELECT DATABASE() AS SelectedDatabase;
SELECT UserID, PublicAlias, AccountStatus FROM `User` WHERE UserID = 1;
SELECT RoleCode FROM UserRole WHERE UserID = 1 AND ActiveMarker = 1;
SELECT UserID, RowVersion FROM BorrowerProfile WHERE UserID = 1;

-- 2
CALL sp_create_loan_request(1, 'Midterm equipment purchase', '300.00', 3);
SET @demo_request = (SELECT MAX(RequestID)  FROM LoanRequest WHERE BorrowerID = 1);
SELECT * FROM v_borrower_requests WHERE RequestID = @demo_request;

-- 3
CALL sp_update_loan_request(1, @demo_request, 0, 'Midterm revised equipment', '600.00', 6);
SELECT RequestID, Purpose, Principal, InstallmentCount, RequestState, RowVersion
FROM LoanRequest WHERE RequestID = @demo_request;

-- 4
CALL sp_cancel_draft(1, 'Borrower', @demo_request, 1,
    'No longer needed for this fictional example.');
SELECT RequestID, Purpose, Principal, InstallmentCount, RequestState,
       TerminalReason, RowVersion
FROM LoanRequest WHERE RequestID = @demo_request;

-- 5
CALL sp_create_loan_request(1, 'Invalid amount example', '99.99', 3);

-- 6
CALL sp_update_loan_request(1, @demo_request, 2, 'Forbidden edit', '300.00', 3);

-- 7
DELETE FROM LoanRequest WHERE RequestID = @demo_request;

-- 8
SELECT RequestID, RequestState, Principal, RowVersion
FROM LoanRequest WHERE RequestID = @demo_request;























-- 9
CALL sp_create_loan_request(1, 'Midterm rollback example', '300.00', 3);
SET @demo_rollback_request = (SELECT MAX(RequestID) FROM LoanRequest WHERE BorrowerID = 1);
SET @demo_events_before = (SELECT COUNT(*) FROM AuditEvent);
SET @demo_changes_before = (SELECT COUNT(*) FROM AuditChange);
SET @demo_fail_audit = 0;
SELECT RequestID, RequestState, RowVersion, TerminalReason
FROM LoanRequest WHERE RequestID = @demo_rollback_request;


-- 10
DELIMITER //
CREATE TRIGGER demo_force_cancel_audit_failure BEFORE INSERT ON AuditChange
FOR EACH ROW
BEGIN
    IF @demo_fail_audit = 1 AND NEW.FieldName = 'TerminalReason' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Demo forced audit failure';
    END IF;
END //
DELIMITER ;

-- 11
SET @demo_fail_audit = 1;

-- 12
CALL sp_cancel_draft(1, 'Borrower', @demo_rollback_request, 0,
    'This cancellation must roll back.');

-- 13
SET @demo_fail_audit = 0;
SELECT RequestID, RequestState, RowVersion, TerminalReason
FROM LoanRequest WHERE RequestID = @demo_rollback_request;
SELECT RequestState = 'Draft' AND RowVersion = 0 AND TerminalReason IS NULL
       AS RollbackPreservedDraft
FROM LoanRequest WHERE RequestID = @demo_rollback_request;
SELECT @demo_events_before AS EventsBefore,
       (SELECT COUNT(*) FROM AuditEvent) AS EventsAfter,
       @demo_changes_before AS ChangesBefore,
       (SELECT COUNT(*) FROM AuditChange) AS ChangesAfter;
SELECT (SELECT COUNT(*) FROM AuditEvent) = @demo_events_before AS AuditEventCountUnchanged,
       (SELECT COUNT(*) FROM AuditChange) = @demo_changes_before AS AuditChangeCountUnchanged;
DROP TRIGGER demo_force_cancel_audit_failure;

-- 14
SELECT e.AuditEventID, e.OccurredAt, e.EventType, e.ActorUserID, e.ActingRoleCode,
       c.FieldName, c.OldValue, c.NewValue
FROM AuditEvent e JOIN AuditChange c ON c.AuditEventID = e.AuditEventID
WHERE e.SubjectType = 'LoanRequest' AND e.SubjectKey = CAST(@demo_request AS CHAR)
ORDER BY e.OccurredAt, e.AuditEventID, c.FieldName;
SELECT COUNT(*) AS LiveRequestEventCount FROM AuditEvent
WHERE SubjectType = 'LoanRequest' AND SubjectKey = CAST(@demo_request AS CHAR);

-- 15
EXPLAIN SELECT RequestID, RequestState, RowVersion
FROM LoanRequest WHERE RequestID = @demo_request;
