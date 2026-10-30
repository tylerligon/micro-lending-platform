CREATE TABLE Permission (
 PermissionCode VARCHAR(40) COLLATE utf8mb4_0900_bin PRIMARY KEY,
 BorrowerScope VARCHAR(16), LenderScope VARCHAR(16), AdministratorScope VARCHAR(16), AuditorScope VARCHAR(16),
 AllowRestricted BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;
CREATE TABLE RolePermission (
 RoleCode VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
 PermissionCode VARCHAR(40) COLLATE utf8mb4_0900_bin NOT NULL,
 ScopeCode VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
 PRIMARY KEY(RoleCode,PermissionCode),
 FOREIGN KEY(RoleCode) REFERENCES `Role`(RoleCode),
 FOREIGN KEY(PermissionCode) REFERENCES Permission(PermissionCode),
 CHECK(ScopeCode IN ('SELF','OWN','PARTICIPATING','ALL'))
) ENGINE=InnoDB;
DELIMITER //
CREATE PROCEDURE sp_lock_policy()
BEGIN
 DECLARE v_Code VARCHAR(16);
 SELECT RoleCode INTO v_Code FROM `Role` WHERE RoleCode='Administrator' FOR UPDATE;
END //
CREATE PROCEDURE sp_auth_lookup(IN p_Login VARCHAR(80))
BEGIN
 SELECT UserID,PasswordHash,AccountStatus FROM `User` WHERE LoginName=p_Login;
END //
CREATE PROCEDURE sp_session_user(IN p_User BIGINT UNSIGNED)
BEGIN
 SELECT UserID,AccountStatus FROM `User` WHERE UserID=p_User;
END //
CREATE PROCEDURE sp_failure_exists(IN p_Context BINARY(16))
BEGIN
 SELECT COUNT(*) AS n FROM AuditEvent WHERE ContextID=p_Context AND Outcome IN ('Denied','Failed');
END //
CREATE PROCEDURE sp_record_failure(IN p_Actor BIGINT UNSIGNED, IN p_Action VARCHAR(64),
 IN p_Reason VARCHAR(40), IN p_Context BINARY(16), IN p_Failed BOOLEAN)
BEGIN
 DECLARE v_User BIGINT UNSIGNED; DECLARE v_Role VARCHAR(16);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 SELECT UserID INTO v_User FROM `User` WHERE UserID=p_Actor;
 SELECT RoleCode INTO v_Role FROM UserRole WHERE UserID=v_User AND ActiveMarker=1 ORDER BY RoleCode LIMIT 1;
 START TRANSACTION;
 INSERT INTO AuditEvent(EventType,Outcome,ActorUserID,ActingRoleCode,TechnicalAccount,SubjectType,SubjectKey,ContextID,ReasonCode)
 SELECT IF(p_Failed,'TransactionFailed','AttemptRejected'),IF(p_Failed,'Failed','Denied'),v_User,v_Role,
 SESSION_USER(),'Attempt',p_Action,p_Context,p_Reason FROM DUAL WHERE NOT EXISTS
 (SELECT 1 FROM AuditEvent WHERE ContextID=p_Context AND Outcome IN ('Denied','Failed'));
 COMMIT;
END //
CREATE PROCEDURE sp_require_permission(IN p_User BIGINT UNSIGNED,IN p_Role VARCHAR(16),
 IN p_Permission VARCHAR(40),IN p_Target BIGINT UNSIGNED,OUT p_Selected VARCHAR(16))
BEGIN
 DECLARE v_Lock VARCHAR(16); DECLARE v_Status VARCHAR(16); DECLARE v_Scope VARCHAR(16);
 DECLARE v_Restricted BOOLEAN; DECLARE v_Owner BIGINT UNSIGNED;
 SET p_Selected=NULL;
 -- Baseline policy mutex; all configuration changes use the same lock.
 SELECT RoleCode INTO v_Lock FROM `Role` WHERE RoleCode='Administrator' FOR UPDATE;
 SELECT AccountStatus INTO v_Status FROM `User` WHERE UserID=p_User FOR UPDATE;
 SELECT ur.RoleCode,rp.ScopeCode,pp.AllowRestricted INTO p_Selected,v_Scope,v_Restricted
 FROM UserRole ur JOIN `Role` r ON r.RoleCode=ur.RoleCode
 JOIN RolePermission rp ON rp.RoleCode=r.RoleCode JOIN Permission pp USING(PermissionCode)
 WHERE ur.UserID=p_User AND ur.ActiveMarker=1 AND r.IsActive=1
 AND (p_Role IS NULL OR r.RoleCode=BINARY p_Role) AND pp.PermissionCode=p_Permission
 ORDER BY ur.RoleCode LIMIT 1 FOR UPDATE;
 IF p_Selected IS NULL OR v_Status IS NULL OR v_Status='Inactive'
 OR (v_Status='Restricted' AND (NOT v_Restricted OR p_Selected IN
 (SELECT RoleCode FROM `Role` WHERE RoleClass IN ('Administrator','Auditor')))) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Permission denied'; END IF;
 IF v_Scope='OWN' THEN
  IF p_Permission='loan.read' THEN
   SELECT r.BorrowerID INTO v_Owner FROM Loan l JOIN LoanRequest r USING(RequestID) WHERE l.LoanID=p_Target;
  ELSE SELECT BorrowerID INTO v_Owner FROM LoanRequest WHERE RequestID=p_Target; END IF;
  IF v_Owner IS NULL OR v_Owner<>p_User THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Owner required'; END IF;
 ELSEIF v_Scope='SELF' AND p_Target IS NOT NULL AND p_Target<>p_User THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Self required';
 ELSEIF v_Scope='PARTICIPATING' AND NOT EXISTS(
 SELECT 1 FROM Loan l JOIN FundingCommitment c ON c.RequestID=l.RequestID
 JOIN OperationReceipt o USING(OperationID) WHERE l.LoanID=p_Target AND c.CommitmentState='Applied' AND o.CallerUserID=p_User) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Participation required'; END IF;
END //
CREATE PROCEDURE sp_protect_access_admin(IN p_User BIGINT UNSIGNED,IN p_Role VARCHAR(16),IN p_Grant BOOLEAN)
BEGIN
 IF NOT p_Grant AND EXISTS(SELECT 1 FROM RolePermission WHERE RoleCode=p_Role AND PermissionCode='permission.manage')
 AND NOT EXISTS(SELECT 1 FROM `User` u JOIN UserRole ur USING(UserID) JOIN `Role` r USING(RoleCode)
 JOIN RolePermission rp USING(RoleCode) WHERE u.UserID<>p_User AND u.AccountStatus='Active'
 AND ur.ActiveMarker=1 AND r.IsActive=1 AND rp.PermissionCode='permission.manage') THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Cannot remove last access administrator'; END IF;
END //
CREATE PROCEDURE sp_configure_role(IN p_Actor BIGINT UNSIGNED,IN p_Code VARCHAR(16),IN p_Class VARCHAR(16),
 IN p_Description VARCHAR(255),IN p_Active BOOLEAN,IN p_Version BIGINT)
BEGIN
 DECLARE v_Role VARCHAR(16); DECLARE v_Old VARCHAR(1000); DECLARE v_Current BIGINT DEFAULT NULL; DECLARE v_ID BIGINT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION
 BEGIN
  DECLARE v_Number INT; DECLARE v_Message TEXT; DECLARE v_Reason VARCHAR(40);
  GET STACKED DIAGNOSTICS CONDITION 1 v_Number=MYSQL_ERRNO,v_Message=MESSAGE_TEXT;
  ROLLBACK;
  SET v_Reason=CASE WHEN v_Number=1213 THEN 'DB_DEADLOCK' WHEN v_Number=1205 THEN 'DB_LOCK_TIMEOUT'
   WHEN v_Message LIKE '%version%' THEN 'STALE_VERSION' WHEN v_Message LIKE '%Owner%' OR v_Message LIKE '%Owned%' THEN 'OWNER_REQUIRED'
   WHEN v_Message LIKE '%Participation%' THEN 'PARTICIPATION_REQUIRED' WHEN v_Message LIKE '%Permission%' THEN 'ROLE_REQUIRED'
   WHEN LOWER(v_Message) LIKE '%audit%failure%' THEN 'INTEGRITY_FAILURE' WHEN v_Number=1644 THEN 'INVALID_INPUT' ELSE 'DB_ERROR' END;
  BEGIN
   DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET @ml_audit_failed=1;
   CALL sp_record_failure(p_Actor,'sp_configure_role',v_Reason,COALESCE(@ml_context,UUID_TO_BIN(UUID())),v_Number<>1644 OR v_Reason='INTEGRITY_FAILURE');
  END;
  RESIGNAL;
 END;
 START TRANSACTION;
 CALL sp_require_permission(p_Actor,NULL,'permission.manage',NULL,v_Role);
 SELECT RowVersion,CONCAT(RoleClass,':',IsActive,':',Description) INTO v_Current,v_Old FROM `Role` WHERE RoleCode=p_Code FOR UPDATE;
 IF p_Code IS NULL OR NOT REGEXP_LIKE(p_Code,'^[A-Za-z][A-Za-z0-9_]{0,15}$','c')
 OR p_Class IS NULL OR p_Class NOT IN ('Borrower','Lender','Administrator','Auditor')
 OR p_Description IS NULL OR CHAR_LENGTH(TRIM(p_Description))=0 OR p_Active IS NULL OR p_Active NOT IN(0,1) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid role'; END IF;
 IF v_Current IS NULL THEN
 IF p_Version IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='New role needs NULL version'; END IF;
 INSERT INTO `Role`(RoleCode,Description,RoleClass,IsActive) VALUES(p_Code,TRIM(p_Description),p_Class,p_Active);
 ELSE
 IF p_Version IS NULL OR p_Version<>v_Current THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Stale role version'; END IF;
 IF EXISTS(SELECT 1 FROM `Role` WHERE RoleCode=p_Code AND RoleClass<>p_Class) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Immutable role category'; END IF;
 IF NOT p_Active AND EXISTS(SELECT 1 FROM UserRole WHERE RoleCode=p_Code AND ActiveMarker=1) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Revoke memberships before retirement'; END IF;
 UPDATE `Role` SET Description=TRIM(p_Description),IsActive=p_Active,RowVersion=RowVersion+1 WHERE RoleCode=p_Code;
 END IF;
 INSERT INTO AuditEvent(EventType,Outcome,ActorUserID,ActingRoleCode,TechnicalAccount,SubjectType,SubjectKey,ContextID)
 VALUES('RoleConfigured','Success',p_Actor,v_Role,SESSION_USER(),'Role',p_Code,COALESCE(@ml_context,UUID_TO_BIN(UUID())));
 SET v_ID=LAST_INSERT_ID();
 INSERT INTO AuditChange VALUES(v_ID,'Configuration',v_Old,CONCAT(p_Class,':',p_Active,':',TRIM(p_Description)));
 COMMIT;
END //
CREATE PROCEDURE sp_configure_permission(IN p_Actor BIGINT UNSIGNED,IN p_Role VARCHAR(16),IN p_Permission VARCHAR(40),
 IN p_Scope VARCHAR(16),IN p_Version BIGINT)
BEGIN
 DECLARE v_ActorRole VARCHAR(16); DECLARE v_Allowed VARCHAR(16); DECLARE v_Current BIGINT DEFAULT NULL;
 DECLARE v_Old VARCHAR(16); DECLARE v_ID BIGINT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION
 BEGIN
  DECLARE v_Number INT; DECLARE v_Message TEXT; DECLARE v_Reason VARCHAR(40);
  GET STACKED DIAGNOSTICS CONDITION 1 v_Number=MYSQL_ERRNO,v_Message=MESSAGE_TEXT;
  ROLLBACK;
  SET v_Reason=CASE WHEN v_Number=1213 THEN 'DB_DEADLOCK' WHEN v_Number=1205 THEN 'DB_LOCK_TIMEOUT'
   WHEN v_Message LIKE '%version%' THEN 'STALE_VERSION' WHEN v_Message LIKE '%Owner%' OR v_Message LIKE '%Owned%' THEN 'OWNER_REQUIRED'
   WHEN v_Message LIKE '%Participation%' THEN 'PARTICIPATION_REQUIRED' WHEN v_Message LIKE '%Permission%' THEN 'ROLE_REQUIRED'
   WHEN LOWER(v_Message) LIKE '%audit%failure%' THEN 'INTEGRITY_FAILURE' WHEN v_Number=1644 THEN 'INVALID_INPUT' ELSE 'DB_ERROR' END;
  BEGIN
   DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET @ml_audit_failed=1;
   CALL sp_record_failure(p_Actor,'sp_configure_permission',v_Reason,COALESCE(@ml_context,UUID_TO_BIN(UUID())),v_Number<>1644 OR v_Reason='INTEGRITY_FAILURE');
  END;
  RESIGNAL;
 END;
 START TRANSACTION;
 CALL sp_require_permission(p_Actor,NULL,'permission.manage',NULL,v_ActorRole);
 SELECT r.RowVersion,CASE r.RoleClass WHEN 'Borrower' THEN p.BorrowerScope WHEN 'Lender' THEN p.LenderScope
 WHEN 'Administrator' THEN p.AdministratorScope ELSE p.AuditorScope END INTO v_Current,v_Allowed
 FROM `Role` r CROSS JOIN Permission p WHERE r.RoleCode=p_Role AND r.IsActive=1 AND p.PermissionCode=p_Permission FOR UPDATE;
 IF v_Current IS NULL OR p_Version IS NULL OR p_Version<>v_Current THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown mapping or stale version'; END IF;
 IF p_Scope IS NOT NULL AND (v_Allowed IS NULL OR BINARY p_Scope<>BINARY v_Allowed) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unsupported scope for role category'; END IF;
 IF p_Permission='permission.manage' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Protected bootstrap capability'; END IF;
 SELECT ScopeCode INTO v_Old FROM RolePermission WHERE RoleCode=p_Role AND PermissionCode=p_Permission;
 IF p_Scope IS NULL THEN DELETE FROM RolePermission WHERE RoleCode=p_Role AND PermissionCode=p_Permission;
 ELSE INSERT INTO RolePermission VALUES(p_Role,p_Permission,p_Scope) ON DUPLICATE KEY UPDATE ScopeCode=p_Scope; END IF;
 UPDATE `Role` SET RowVersion=RowVersion+1 WHERE RoleCode=p_Role;
 INSERT INTO AuditEvent(EventType,Outcome,ActorUserID,ActingRoleCode,TechnicalAccount,SubjectType,SubjectKey,ContextID)
 VALUES('PermissionConfigured','Success',p_Actor,v_ActorRole,SESSION_USER(),'RolePermission',CONCAT(p_Role,'/',p_Permission),COALESCE(@ml_context,UUID_TO_BIN(UUID())));
 SET v_ID=LAST_INSERT_ID(); INSERT INTO AuditChange VALUES(v_ID,'Configuration',v_Old,p_Scope);
 COMMIT;
END //
CREATE PROCEDURE sp_read_requests(IN p_Actor BIGINT UNSIGNED,IN p_Request BIGINT UNSIGNED)
BEGIN
 DECLARE v_Role VARCHAR(16); DECLARE EXIT HANDLER FOR SQLEXCEPTION
 BEGIN
  DECLARE v_Number INT; DECLARE v_Message TEXT; DECLARE v_Reason VARCHAR(40);
  GET STACKED DIAGNOSTICS CONDITION 1 v_Number=MYSQL_ERRNO,v_Message=MESSAGE_TEXT;
  ROLLBACK;
  SET v_Reason=CASE WHEN v_Number=1213 THEN 'DB_DEADLOCK' WHEN v_Number=1205 THEN 'DB_LOCK_TIMEOUT'
   WHEN v_Message LIKE '%version%' THEN 'STALE_VERSION' WHEN v_Message LIKE '%Owner%' OR v_Message LIKE '%Owned%' THEN 'OWNER_REQUIRED'
   WHEN v_Message LIKE '%Participation%' THEN 'PARTICIPATION_REQUIRED' WHEN v_Message LIKE '%Permission%' THEN 'ROLE_REQUIRED'
   WHEN LOWER(v_Message) LIKE '%audit%failure%' THEN 'INTEGRITY_FAILURE' WHEN v_Number=1644 THEN 'INVALID_INPUT' ELSE 'DB_ERROR' END;
  BEGIN
   DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET @ml_audit_failed=1;
   CALL sp_record_failure(p_Actor,'sp_read_requests',v_Reason,COALESCE(@ml_context,UUID_TO_BIN(UUID())),v_Number<>1644 OR v_Reason='INTEGRITY_FAILURE');
  END;
  RESIGNAL;
 END;
 START TRANSACTION; CALL sp_require_permission(p_Actor,NULL,'request.read',p_Request,v_Role);
 SELECT RequestID,BorrowerID,Purpose,Principal,InstallmentCount,RequestState,RowVersion FROM LoanRequest WHERE RequestID=p_Request;
 COMMIT;
END //
CREATE PROCEDURE sp_read_loan(IN p_Actor BIGINT UNSIGNED,IN p_Loan BIGINT UNSIGNED)
BEGIN
 DECLARE v_Role VARCHAR(16); DECLARE EXIT HANDLER FOR SQLEXCEPTION
 BEGIN
  DECLARE v_Number INT; DECLARE v_Message TEXT; DECLARE v_Reason VARCHAR(40);
  GET STACKED DIAGNOSTICS CONDITION 1 v_Number=MYSQL_ERRNO,v_Message=MESSAGE_TEXT;
  ROLLBACK;
  SET v_Reason=CASE WHEN v_Number=1213 THEN 'DB_DEADLOCK' WHEN v_Number=1205 THEN 'DB_LOCK_TIMEOUT'
   WHEN v_Message LIKE '%version%' THEN 'STALE_VERSION' WHEN v_Message LIKE '%Owner%' OR v_Message LIKE '%Owned%' THEN 'OWNER_REQUIRED'
   WHEN v_Message LIKE '%Participation%' THEN 'PARTICIPATION_REQUIRED' WHEN v_Message LIKE '%Permission%' THEN 'ROLE_REQUIRED'
   WHEN LOWER(v_Message) LIKE '%audit%failure%' THEN 'INTEGRITY_FAILURE' WHEN v_Number=1644 THEN 'INVALID_INPUT' ELSE 'DB_ERROR' END;
  BEGIN
   DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET @ml_audit_failed=1;
   CALL sp_record_failure(p_Actor,'sp_read_loan',v_Reason,COALESCE(@ml_context,UUID_TO_BIN(UUID())),v_Number<>1644 OR v_Reason='INTEGRITY_FAILURE');
  END;
  RESIGNAL;
 END;
 START TRANSACTION; CALL sp_require_permission(p_Actor,NULL,'loan.read',p_Loan,v_Role);
 SELECT * FROM v_loan_balances WHERE LoanID=p_Loan;
 SELECT * FROM v_installment_remaining WHERE LoanID=p_Loan ORDER BY InstallmentNumber; COMMIT;
END //
DELIMITER ;
