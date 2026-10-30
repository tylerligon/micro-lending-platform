CREATE TEMPORARY TABLE ent_guard (Safe INT CHECK(Safe=1));
INSERT INTO ent_guard SELECT DATABASE()='micro_lending_midterm_test';
DROP TEMPORARY TABLE ent_guard;
-- Run after midterm seed/demo in isolated test DB. Test helpers removed on success.
DELIMITER //
CREATE PROCEDURE ent_assert(IN ok BOOLEAN)
BEGIN IF ok IS NULL OR NOT ok THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Entitlement assertion failed'; END IF; END //
CREATE PROCEDURE ent_reject(IN q TEXT)
BEGIN
 DECLARE failed BOOLEAN DEFAULT FALSE;
 SET @q=q; PREPARE st FROM @q;
 BEGIN DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed=TRUE; EXECUTE st; END;
 DEALLOCATE PREPARE st; CALL ent_assert(failed);
END //
DELIMITER ;
-- Administrator in fixture is user 5 (user 6 is Auditor).
CALL sp_configure_role(5,'Assistant','Borrower','Limited borrower',1,NULL);
CALL ent_assert((SELECT COUNT(*)=0 FROM RolePermission WHERE RoleCode='Assistant'));
CALL sp_configure_permission(5,'Assistant','request.cancel','OWN',0);
CALL ent_reject("CALL sp_configure_permission(5,'Assistant','request.cancel','ALL',1)");
CALL ent_reject("CALL sp_configure_permission(5,'Assistant','user.create','ALL',1)");
CALL ent_reject("CALL sp_configure_permission(5,'Assistant','permission.manage','ALL',1)");
CALL ent_reject("CALL sp_configure_permission(1,'Assistant','request.cancel',NULL,1)");
CALL ent_reject("CALL sp_configure_permission(5,'Assistant','request.cancel',NULL,0)");
CALL sp_set_role(5,1,'Assistant',1);
CALL sp_create_loan_request(1,'Entitlement custom role test','300',3);
SET @rid=LAST_INSERT_ID();
-- LAST_INSERT_ID is audit ID after procedure; discover test row by unique purpose.
SET @rid=(SELECT RequestID FROM LoanRequest WHERE Purpose='Entitlement custom role test');
CALL ent_reject('CALL sp_cancel_draft(4,\'Borrower\',@rid,0,\'Wrong owner\')');
CALL sp_configure_permission(5,'Borrower','request.cancel',NULL,(SELECT RowVersion FROM `Role` WHERE RoleCode='Borrower'));
CALL ent_reject('CALL sp_cancel_draft(1,\'Borrower\',@rid,0,\'Revoked\')');
CALL sp_cancel_draft(1,'Assistant',@rid,0,'Custom role works');
CALL ent_assert((SELECT COUNT(*)=1 FROM AuditEvent WHERE EventType='RequestCancelled' AND ActingRoleCode='Assistant' AND SubjectKey=CAST(@rid AS CHAR)));
CALL sp_configure_permission(5,'Borrower','request.cancel','OWN',(SELECT RowVersion FROM `Role` WHERE RoleCode='Borrower'));
CALL sp_read_loan(2,501);
CALL ent_reject('CALL sp_read_loan(2,502)');
CALL ent_reject('CALL sp_read_loan(7,501)');
CALL ent_reject("CALL sp_set_role(5,1,'Auditor',1)");
CALL ent_reject("CALL sp_set_role(5,5,'Administrator',0)");
CALL ent_reject("CALL sp_configure_role(5,'Administrator','Administrator','Retire',0,0)");
CALL ent_assert((SELECT COUNT(*)>=3 FROM AuditEvent WHERE EventType IN('RoleConfigured','PermissionConfigured')));
CALL ent_reject("CALL sp_set_role(5,1,'Assistant',0)");
CALL sp_configure_role(5,'Unused','Borrower','Unassigned',1,NULL);
CALL sp_configure_role(5,'Unused','Borrower','Retired limited borrower',0,0);
CALL ent_reject("CALL sp_set_role(5,1,'Unused',1)");
DROP PROCEDURE ent_reject;
DROP PROCEDURE ent_assert;
SELECT 'PASS entitlement grant/revoke, custom role, scope, version, separation and bootstrap checks' AS Result;
