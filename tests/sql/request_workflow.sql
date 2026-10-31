-- Run after the fictional midterm fixture and entitlement tests, in a disposable DB.
CREATE TEMPORARY TABLE wf_guard (Safe INT CHECK(Safe=1));
INSERT INTO wf_guard SELECT DATABASE()='micro_lending_midterm_test';
DROP TEMPORARY TABLE wf_guard;
DELIMITER //
CREATE PROCEDURE wf_assert(IN ok BOOLEAN, IN message TEXT)
BEGIN IF ok IS NULL OR NOT ok THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=message; END IF; END //
CREATE PROCEDURE wf_reject(IN statement_text TEXT)
BEGIN
 DECLARE failed BOOLEAN DEFAULT FALSE;
 SET @wf_sql=statement_text; PREPARE wf_statement FROM @wf_sql;
 BEGIN DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed=TRUE; EXECUTE wf_statement; END;
 DEALLOCATE PREPARE wf_statement;
 CALL wf_assert(failed,'Expected workflow rejection');
END //
CREATE TRIGGER wf_force_audit_failure BEFORE INSERT ON AuditEvent FOR EACH ROW
BEGIN
 IF COALESCE(@wf_fail,0)=1 AND NEW.EventType='WorkflowConfigured' THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Workflow audit failure';
 END IF;
END //
DELIMITER ;

CALL wf_assert((SELECT COUNT(*)=4 FROM RequestWorkflowTransition),'Four implemented rules');
CALL wf_reject("INSERT INTO RequestWorkflowAction VALUES('Unknown','nonexistent.permission','RequestSaved')");
CALL wf_reject("INSERT INTO RequestWorkflowTransition VALUES('EditDraft','Missing','Draft',1,0)");
CALL wf_reject("INSERT INTO RequestWorkflowTransition VALUES('EditDraft','Submitted','Missing',1,0)");
CALL wf_reject("INSERT INTO RequestWorkflowTransition VALUES('EditDraft','Draft','Submitted',1,0)");
CALL wf_reject("INSERT INTO RequestWorkflowTransition VALUES('EditDraft','Submitted','NotCreated',1,0)");
CALL wf_reject("CALL sp_set_request_transition(1,'EditDraft','Draft',0,0)");
CALL wf_reject("CALL sp_set_request_transition(5,'EditDraft','Draft',NULL,0)");
CALL wf_reject("CALL sp_set_request_transition(5,'AssessRequest','Submitted',1,0)");

-- No code change: disable a seeded row and the existing command stops accepting it.
SET @wf_before=(SELECT COUNT(*) FROM LoanRequest);
CALL sp_set_request_transition(5,'CreateDraft','NotCreated',0,0);
CALL wf_reject("CALL sp_create_loan_request(1,'Disabled create','300',3)");
CALL wf_assert((SELECT COUNT(*)=@wf_before FROM LoanRequest),'Disabled create changed records');
CALL sp_set_request_transition(5,'CreateDraft','NotCreated',1,1);
CALL sp_create_loan_request(1,'Workflow policy test','300',3);
SET @wf_request=(SELECT RequestID FROM LoanRequest WHERE Purpose='Workflow policy test');
CALL sp_set_request_transition(5,'EditDraft','Draft',0,0);
CALL wf_reject("CALL sp_update_loan_request(1,@wf_request,0,'Must not change','600',6)");
CALL wf_assert((SELECT Principal=300 AND RowVersion=0 FROM LoanRequest WHERE RequestID=@wf_request),'Disabled edit changed records');
CALL wf_reject("CALL sp_set_request_transition(5,'EditDraft','Draft',1,0)");
CALL sp_set_request_transition(5,'EditDraft','Draft',1,1);
CALL sp_update_loan_request(1,@wf_request,0,'Workflow policy test','600',6);
CALL wf_assert((SELECT Principal=600 AND RowVersion=1 AND RequestState='Draft' FROM LoanRequest WHERE RequestID=@wf_request),'Enabled edit failed');

CALL sp_set_request_transition(5,'SubmitRequest','Draft',0,0);
CALL wf_reject('CALL sp_prepare_submission(1,@wf_request,1)');
CALL wf_assert((SELECT RequestState='Draft' AND RowVersion=1 FROM LoanRequest WHERE RequestID=@wf_request),'Disabled submit changed records');
CALL wf_assert((SELECT COUNT(*)=0 FROM RequestEvaluation WHERE RequestID=@wf_request),'Disabled submit inserted evaluation');
CALL sp_set_request_transition(5,'SubmitRequest','Draft',1,1);
CALL sp_set_request_transition(5,'CancelDraft','Draft',0,0);
CALL wf_reject("CALL sp_cancel_draft(1,'Borrower',@wf_request,1,'Not yet')");
CALL sp_set_request_transition(5,'CancelDraft','Draft',1,1);
CALL sp_cancel_draft(1,'Borrower',@wf_request,1,'Finished workflow test');
CALL wf_assert((SELECT RequestState='Cancelled' AND RowVersion=2 FROM LoanRequest WHERE RequestID=@wf_request),'Enabled cancel failed');
CALL wf_reject("CALL sp_update_loan_request(1,@wf_request,2,'Terminal edit','300',3)");
CALL wf_reject('CALL sp_prepare_submission(1,@wf_request,2)');
CALL wf_reject("CALL sp_cancel_draft(1,'Borrower',@wf_request,2,'Duplicate cancellation')");
CALL wf_assert((SELECT COUNT(*)=3 FROM AuditEvent WHERE SubjectType='LoanRequest' AND SubjectKey=CAST(@wf_request AS CHAR) AND Outcome='Success'),'Rejected commands added success audits');
CALL wf_assert((SELECT COUNT(*)=8 FROM AuditEvent WHERE EventType='WorkflowConfigured'),'Configuration audit missing');

-- A required audit-write failure must roll back the policy change too.
SET @wf_fail=1;
CALL wf_reject("CALL sp_set_request_transition(5,'EditDraft','Draft',0,2)");
SET @wf_fail=0;
CALL wf_assert((SELECT IsEnabled=1 AND RowVersion=2 FROM RequestWorkflowTransition WHERE ActionCode='EditDraft' AND FromState='Draft'),'Failed audit left changed policy');
CALL wf_assert((SELECT COUNT(*)=8 FROM AuditEvent WHERE EventType='WorkflowConfigured'),'Partial configuration audit survived');

-- Lender 2's new Borrower role must not mask their valid participating grant.
CALL sp_set_role(5,2,'Borrower',1);
START TRANSACTION;
CALL sp_require_permission(2,NULL,'loan.read',501,@wf_role);
CALL wf_assert(@wf_role='Lender','Wrong matching scoped role selected');
COMMIT;
CALL sp_read_loan(2,501);
CALL wf_reject('CALL sp_read_loan(2,502)');
CALL wf_reject('CALL sp_read_loan(7,501)');

-- Binary UUID contexts must never be coerced to a UTF-8 string.
SET @ml_context=UNHEX('FF000102030405060708090A0B0C0D0E');
CALL wf_assert(fn_action_context()=@ml_context,'Binary action context changed');
SET @ml_context=NULL;
CALL wf_assert(OCTET_LENGTH(fn_action_context())=16,'Generated context size');
DROP TRIGGER wf_force_audit_failure;
DROP PROCEDURE wf_assert;
DROP PROCEDURE wf_reject;
SELECT 'PASS workflow rules, FK integrity, disabled actions, versions, terminal states, atomic audit and dual-role access' AS Result;
